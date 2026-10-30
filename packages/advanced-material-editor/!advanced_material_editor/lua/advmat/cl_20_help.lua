--[[---------------------------------------------------------------------------
	Advanced Material Editor - parameter help

	The one-line descriptions in the parameter database are labels: enough to
	tell two sliders apart once you already know what they do. This is the
	longer form behind the "?" on each row, written for someone who has never
	opened a .vmt.

	House style, so they stay useful:
	  * say what it DOES before what it is
	  * name the thing you would actually try, with a number where one helps
	  * say what it depends on and what breaks, because that is what costs
	    people an afternoon
	  * no Source jargon that is not defined on the spot

	Parameters without an entry fall back to their database description, so
	adding to this table is always safe and never required.

	Clientside only: nothing on the server ever reads it.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local HELP_EN = {
	[ "help.none" ] = "No description available for this parameter.",
	[ "help.bool" ] = "On or off", [ "help.int" ] = "Whole number",
	[ "help.float" ] = "Number", [ "help.color" ] = "Colour",
	[ "help.vector2" ] = "Two numbers", [ "help.vector3" ] = "Three numbers",
	[ "help.vector4" ] = "Four numbers",
	[ "help.texture" ] = "Texture path", [ "help.text" ] = "Text",
	[ "help.transform" ] = "Texture transform", [ "help.value" ] = "Value",
	[ "help.default" ] = "default {{value}}",
	[ "help.range" ] = "usual range {{min}} to {{max}}",
	[ "help.needs" ] = "needs {{value}}",
	[ "help.rebuild" ] = "rebuilds the material when changed",
}

local function LocalHelp( key, variables )
	if AdvMat.L then return AdvMat.L( key, variables ) end
	local text = HELP_EN[ key ] or key
	if variables then
		text = string.gsub( text, "{{%s*([%w_]+)%s*}}", function( name )
			return tostring( variables[ name ] or "{{" .. name .. "}}" )
		end )
	end
	return text
end

AdvMat.HELP = {

	---------------------------------------------------------------- base
	[ "$basetexture" ] =
		"The main colour image of the surface - the paint, not the shape. " ..
		"Everything else here layers on top of it.\n\n" ..
		"Paths start inside materials/ and leave the extension off, so " ..
		"materials/models/kleiner/kleiner_sheet.vtf is written as " ..
		"models/kleiner/kleiner_sheet.\n\n" ..
		"Its alpha channel is shared: transparency, the phong mask and the " ..
		"reflection mask all read it unless you point them somewhere else.",

	[ "$frame" ] =
		"Which frame of an animated texture to start on. Only does anything " ..
		"if the .vtf actually contains several frames; on a normal texture it " ..
		"is ignored.",

	[ "$model" ] =
		"Marks the material as belonging to a model rather than to map " ..
		"geometry. It is on automatically for anything this editor builds, and " ..
		"turning it off will usually make the surface render wrong.",

	[ "$surfaceprop" ] =
		"The physical material: what it sounds like when shot, what particles " ..
		"come off it, how slippery it is. Try metal, flesh, glass, wood, dirt. " ..
		"Purely a gameplay property - it changes nothing visually.",

	--------------------------------------------------------------- tint
	[ "$color2" ] =
		"Tints the whole material. [1 1 1] is untouched; [1 0.5 0.5] leaves " ..
		"red alone and halves green and blue, giving a red tint.\n\n" ..
		"Values above 1 brighten. This is the tint to reach for on models: it " ..
		"is applied after lighting, so shadows stay shadows.",

	[ "$color" ] =
		"An older tint that is applied before lighting, which tends to wash " ..
		"the surface out. $color2 does the same job better on models - use " ..
		"this one only if $color2 is doing nothing.",

	[ "$blendtintbybasealpha" ] =
		"Restricts $color2 to the parts of the texture whose alpha is white. " ..
		"This is how team colours are done: paint a mask into the alpha " ..
		"channel and only that region gets tinted.\n\n" ..
		"It takes over the alpha channel, so it cannot be combined with " ..
		"alpha-based transparency.",

	[ "$blendtintcoloroverbase" ] =
		"How the tint mixes inside the masked area. 0 multiplies the tint into " ..
		"the texture, keeping its detail. 1 replaces the texture with flat " ..
		"colour. Values in between fade between the two.",

	[ "$desaturatewithbasealpha" ] =
		"Drains colour out of the texture, using its own alpha channel to " ..
		"decide where. 0 leaves it alone, 1 makes the masked area greyscale.",

	------------------------------------------------------- transparency
	[ "$translucent" ] =
		"Makes the surface see-through, using the alpha channel of " ..
		"$basetexture. Black alpha is invisible, white is solid, grey is " ..
		"partly there.\n\n" ..
		"The catch is sorting: the engine draws each translucent surface as a " ..
		"whole, so two translucent parts of the same model can end up in the " ..
		"wrong order and look inside-out. For hair, leaves, chain fences and " ..
		"anything with hard edges, use $alphatest instead - it is cheaper and " ..
		"it sorts correctly.",

	[ "$alphatest" ] =
		"Hard-edged transparency: every pixel is either fully there or fully " ..
		"gone, decided by the alpha channel of $basetexture. No half-" ..
		"transparency.\n\n" ..
		"Almost always the right choice for hair, foliage, grates and cloth " ..
		"cutouts. It sorts correctly and costs far less than $translucent.",

	[ "$alphatestreference" ] =
		"The cutoff for $alphatest. A pixel survives if its alpha is above " ..
		"this. Lower keeps more of the texture, higher trims it back.\n\n" ..
		"0.5 is the usual starting point. If hair looks chewed away, lower it " ..
		"towards 0.3; if you see a halo of leftover pixels, raise it.",

	[ "$allowalphatocoverage" ] =
		"Softens the hard edge $alphatest leaves behind by using the game's " ..
		"anti-aliasing to fade it. Only does anything when the player has MSAA " ..
		"turned on.",

	[ "$additive" ] =
		"Adds the material to whatever is behind it instead of covering it. " ..
		"Black becomes completely invisible and bright areas glow.\n\n" ..
		"Right for fire, energy, holograms and glass highlights. Wrong for " ..
		"anything that should look solid.",

	[ "$alpha" ] =
		"Fades the entire material evenly. 1 is solid, 0 is invisible. Unlike " ..
		"$translucent this ignores the texture's alpha channel and dims " ..
		"everything at once.",

	[ "$nocull" ] =
		"Draws both sides of every triangle. Turn this on when a single-sided " ..
		"surface - a cape, a skirt, a leaf - vanishes when seen from behind. " ..
		"It doubles the cost of drawing that surface.",

	[ "$vertexcolor" ] =
		"Lets the model's own painted-in vertex colours tint the material. " ..
		"Does nothing unless the model was built with them.",

	[ "$vertexalpha" ] =
		"Lets the model's painted-in vertex transparency fade the material. " ..
		"Does nothing unless the model was built with it.",

	----------------------------------------------------------- bump map
	[ "$bumpmap" ] =
		"A normal map: the shape of the surface, stored as colour. It makes " ..
		"light behave as if there were bumps, seams and wrinkles, without " ..
		"adding any actual geometry.\n\n" ..
		"A normal map looks mostly pale blue-lilac. If a texture looks like a " ..
		"photograph, it is not one. Use the Gen button to build one from a " ..
		"colour texture.\n\n" ..
		"Two things to know. Its alpha channel is the default mask for phong " ..
		"and reflections. And bump mapping needs tangent data compiled into " ..
		"the model, so on a model that was built without it, adding a bump map " ..
		"does nothing no matter what you set here.",

	[ "$bumpframe" ] =
		"Starting frame for an animated normal map. Ignored on a normal one.",

	[ "$bumptransform" ] =
		"Scales, rotates and slides the normal map independently of the colour " ..
		"texture. Use it to tile fine detail more densely than the paint.",

	[ "$ssbump" ] =
		"Says the normal map is a self-shadowing bump map, a different format " ..
		"that stores light directions instead of surface angles. Only switch " ..
		"this on if the texture was made that way - on a normal map it makes " ..
		"the lighting go strange.",

	[ "$normalmapalphaenvmapmask" ] =
		"Use the normal map's alpha channel to decide where reflections show, " ..
		"instead of the colour texture's alpha. Frees the colour alpha up for " ..
		"transparency.",

	-------------------------------------------------------------- phong
	[ "$phong" ] =
		"Turns on the soft, wrapping shine that Source uses for skin, leather, " ..
		"latex and wet surfaces. It is the single biggest visual upgrade for a " ..
		"character model.\n\n" ..
		"It needs a $bumpmap - without one it does nothing at all. By default " ..
		"the normal map's alpha channel decides where the shine appears: white " ..
		"is shiny, black is matte.",

	[ "$phongboost" ] =
		"How bright the shine is. Skin sits around 1 to 2, polished leather or " ..
		"wet plastic around 5 to 20. Push it far and everything looks like it " ..
		"has been oiled.",

	[ "$phongexponent" ] =
		"How tight the shine is. Low numbers give a broad soft sheen like " ..
		"skin; high numbers give a small sharp glint like polished metal.\n\n" ..
		"Try 5 for skin, 20 to 40 for plastic, 60 and up for metal.\n\n" ..
		"Any value above 0 here completely replaces $phongexponenttexture. If " ..
		"you have generated an exponent map and nothing seems to have changed, " ..
		"this is why - set it to 0 to hand control back to the texture.",

	[ "$phongexponenttexture" ] =
		"Lets tightness vary across the surface instead of being one number, " ..
		"which is how you make skin and a leather belt shine differently on " ..
		"one texture sheet.\n\n" ..
		"Its channels each mean something: red is the tightness, green is how " ..
		"much the highlight picks up the surface colour, and alpha masks the " ..
		"rim light.",

	[ "$phongexponentfactor" ] =
		"Multiplies whatever the exponent texture says, so you can make the " ..
		"whole surface sharper or softer without repainting it.\n\n" ..
		"Two traps. Its default of 0 means \"not in use\" rather than \"flat\", " ..
		"and the value that reproduces normal behaviour is 149, not 1. And it " ..
		"belongs to Team Fortress 2 and Source 2013, so it may simply be " ..
		"ignored here.",

	[ "$phongalbedotint" ] =
		"Lets the highlight take on the colour underneath it rather than being " ..
		"white. A red surface gets a red sheen. Needs $phongexponenttexture, " ..
		"whose green channel controls how much.",

	[ "$phongalbedoboost" ] =
		"Strengthens the colour-tinted part of the highlight from " ..
		"$phongalbedotint.",

	[ "$phongtint" ] =
		"Colours the highlight directly. [1 1 1] is white. Warm skin often " ..
		"reads better with something like [1 0.8 0.7].",

	[ "$phongfresnelranges" ] =
		"Controls how the shine changes with viewing angle - real surfaces are " ..
		"shinier when you look along them than straight at them.\n\n" ..
		"The three numbers are head-on, mid-angle and edge-on. [0 0.5 1] is a " ..
		"natural falloff. [1 1 1] turns the effect off and shines evenly. " ..
		"[0 1 0] gives a strong band around the middle.",

	[ "$phongwarptexture" ] =
		"A lookup image that recolours the highlight as it falls off, used for " ..
		"iridescent and pearlescent finishes.",

	[ "$phongdisablehalflambert" ] =
		"Stops $halflambert from softening the shine as well as the diffuse " ..
		"light. Turn on if the highlight looks washed out on a half-lambert " ..
		"material.",

	[ "$basemapalphaphongmask" ] =
		"Take the phong mask from the colour texture's alpha instead of the " ..
		"normal map's. Handy when the normal map's alpha is already doing " ..
		"something else.",

	[ "$basemapluminancephongmask" ] =
		"Meant to use the brightness of the colour texture as the phong mask - " ..
		"bright areas shine, dark areas do not.\n\n" ..
		"It does not work in Garry's Mod. Setting it here will not do anything; " ..
		"use $basemapalphaphongmask, or paint a mask into the normal map's alpha " ..
		"channel with the normal map generator.",

	[ "$invertphongmask" ] =
		"Despite the name, in Garry's Mod this does NOT invert the phong mask.\n\n" ..
		"The shipped shader only uses this value inside the reflection code, so " ..
		"what it actually flips is the $envmap mask, and only when $envmap is set. " ..
		"That makes it a free way to reverse a reflection mask you cannot repaint, " ..
		"and useless for the thing it is named after.",

	[ "$phongmaskcontrastbrightness" ] =
		"Adjusts the mask before it is used: the first number is contrast, the " ..
		"second brightness.\n\n" ..
		"This is a brush shader parameter. On a model it is simply not read, so " ..
		"changing it here will do nothing.",

	---------------------------------------------------------- rim light
	[ "$rimlight" ] =
		"Adds a soft glow around the silhouette, as if light were spilling " ..
		"round the edges. It lifts a character off the background and is very " ..
		"common on stylised models.\n\n" ..
		"Requires $phong. Its brightness follows the ambient light of the " ..
		"room, so it is subtle in a dark corner and strong outdoors.",

	[ "$rimlightexponent" ] =
		"How tight the rim band is. Higher hugs the outline more closely; " ..
		"lower spreads the glow further inwards. 2 to 8 is the useful range.",

	[ "$rimlightboost" ] =
		"How bright the rim glow is. Past about 4 it starts to look like the " ..
		"character is on fire, which may well be the point.",

	[ "$rimmask" ] =
		"Restricts the rim light using the alpha channel of " ..
		"$phongexponenttexture, so you can keep it off cloth and on skin.",

	-------------------------------------------------------- reflections
	[ "$envmap" ] =
		"Makes the surface reflect its surroundings. Set it to env_cubemap and " ..
		"it picks up the nearest reflection probe the map author placed, which " ..
		"is what you want almost every time.\n\n" ..
		"By default the reflection shows everywhere. Add a mask, or turn on " ..
		"$normalmapalphaenvmapmask, to keep it off the parts that should stay " ..
		"matte.",

	[ "$envmaptint" ] =
		"How strong the reflection is, per colour channel. [1 1 1] is full " ..
		"strength; [0.1 0.1 0.1] is a faint sheen. This is usually the first " ..
		"thing to turn down - full-strength reflections look like chrome.",

	[ "$envmapmask" ] =
		"A greyscale image deciding where the reflection appears. White " ..
		"reflects, black does not.\n\n" ..
		"Worth reading before you use it: the engine only looks at this texture " ..
		"on a material with NO bump map and NO $phong. Nearly every playermodel " ..
		"has both, and on one of those the shader ignores this and switches " ..
		"$envmap off as well - so adding a mask removes the reflection instead " ..
		"of shaping it.\n\n" ..
		"On a material like that the mask has to live in the alpha channel of " ..
		"the normal map instead, and the normal map generator can put one there.\n\n" ..
		"It also does nothing at all unless $envmap is set.",

	[ "$basealphaenvmapmask" ] =
		"Use the colour texture's alpha as the reflection mask. Cannot be " ..
		"combined with $translucent, since both want the same channel.",

	[ "$envmapcontrast" ] =
		"Deepens the reflection. 0 leaves it as it is; 1 darkens everything " ..
		"except the bright spots, which makes the surface read as harder and " ..
		"more polished.",

	[ "$envmapsaturation" ] =
		"How colourful the reflection is. 0 makes it greyscale, 1 keeps the " ..
		"full colour of the surroundings.",

	[ "$envmapfresnel" ] =
		"Fades the reflection in towards glancing angles, the way real " ..
		"surfaces behave - a floor is mirror-like across the room and dull " ..
		"underfoot. 1 is the full effect.",

	[ "$envmaplightscale" ] =
		"Dims the reflection in dark places, so a shiny surface stops glowing " ..
		"in an unlit room. 0 is off, 1 ties the reflection fully to the light.",

	[ "$envmapanisotropy" ] =
		"Stretches the reflection along the surface, the way brushed metal " ..
		"smears a highlight into a line.",

	---------------------------------------------------- self illumination
	[ "$selfillum" ] =
		"Makes parts of the material glow on their own, ignoring the lighting " ..
		"around them - screens, eyes, runes, hot metal.\n\n" ..
		"By default the alpha channel of $basetexture decides where: white " ..
		"glows, black does not. If that channel is already used for " ..
		"transparency, point $selfillummask at a separate image instead.\n\n" ..
		"It does not light anything else up; only this surface brightens.",

	[ "$selfillummask" ] =
		"A dedicated image saying where the glow is, which leaves the colour " ..
		"texture's alpha free for transparency. White glows, black does not.",

	[ "$selfillumtint" ] =
		"Colours the glowing areas. Values above 1 push it bright enough to " ..
		"bloom.",

	[ "$selfillumfresnel" ] =
		"Varies the glow by viewing angle, so it flares as the surface turns " ..
		"away. Good for screens and eyes.",

	[ "$selfillumfresnelminmaxexp" ] =
		"Shapes that angle falloff: minimum glow, maximum glow, and how " ..
		"sharply it moves between them.",

	------------------------------------------------------ detail texture
	[ "$detail" ] =
		"A second texture tiled far more densely than the first, to add close-" ..
		"up grain - skin pores, fabric weave, concrete speckle - that the main " ..
		"texture has no resolution for.\n\n" ..
		"It only shows up close, which is the point: it costs almost nothing " ..
		"and stops surfaces going flat when the camera comes near.",

	[ "$detailscale" ] =
		"How many times the detail texture repeats across the main one. 4 is " ..
		"gentle, 20 or more gives fine grain. Too high and it turns to noise.",

	[ "$detailblendfactor" ] =
		"How strongly the detail shows. Start low, around 0.2 to 0.5 - detail " ..
		"is meant to be felt rather than seen.",

	[ "$detailblendmode" ] =
		"How the detail texture combines with the colour underneath. 0 " ..
		"multiplies it in, which darkens; 1 adds it, which brightens; 7 is " ..
		"mod2x, where mid-grey leaves the surface untouched and lighter or " ..
		"darker pixels push it either way. 7 is usually the one you want for " ..
		"grain.",

	[ "$detailtint" ] =
		"Colours the detail texture before it is blended in.",

	--------------------------------------------------------- lighting
	[ "$halflambert" ] =
		"Softens how light falls off, so the unlit side of a surface stays " ..
		"visible instead of going black. It is what stops Half-Life 2 " ..
		"characters looking like they are half in shadow, and it suits stylised " ..
		"and anime-styled models especially well.\n\n" ..
		"Costs nothing. Worth trying on any character that looks too contrasty.",

	[ "$lightwarptexture" ] =
		"A one-pixel-tall gradient that rewrites how light becomes brightness. " ..
		"The engine looks up the gradient from left (unlit) to right (fully " ..
		"lit) instead of shading smoothly.\n\n" ..
		"This is how cel shading is done: a gradient with two flat bands gives " ..
		"hard-edged toon lighting. A warm-to-cool gradient gives a painterly " ..
		"look instead.",

	[ "$notint" ] =
		"Ignores the colour set on the entity by the Colour tool or by Lua, so " ..
		"this material keeps its own colours no matter what.",

	[ "$receiveflashlight" ] =
		"Lets the flashlight and projected textures light this material even " ..
		"when it is translucent, which they otherwise skip.",

	[ "$nodecal" ] =
		"Bullet holes, blood and spray decals will not stick to this surface. " ..
		"Model decal rendering is exposed to Lua per prop rather than per " ..
		"sub-material, so enabling this on any slot suppresses decals on the " ..
		"whole prop. Existing decals are cleared when the setting changes.",

	---------------------------------------------------------- transforms
	[ "$basetexturetransform" ] =
		"Moves, scales and rotates the colour texture across the surface " ..
		"without touching the model's own UVs.\n\n" ..
		"Scale above 1 tiles the texture more times and makes it smaller; " ..
		"below 1 zooms in. Translate slides it, and 1 is one full tile. " ..
		"Centre is the pivot that scale and rotate work around, and 0.5 0.5 - " ..
		"the middle - is almost always right.",

	[ "$detailtexturetransform" ] =
		"Moves, scales and rotates the detail texture. Note that $detailscale " ..
		"already handles tiling, so this is mostly for rotating grain off the " ..
		"grid.",

	[ "$envmapmasktransform" ] =
		"Moves, scales and rotates the reflection mask.",

	-------------------------------------------------------------- flags
	[ "$ignorez" ] =
		"Draws the surface through walls, so it is visible from anywhere on " ..
		"the map. An x-ray effect, not a subtle one.",

	[ "$wireframe" ] =
		"Draws only the edges of the triangles. Useful for seeing how a model " ..
		"is built.",

	[ "$flat" ] =
		"Skips lighting entirely and draws the texture at full brightness.",

	[ "$nofog" ] =
		"Exempts the surface from the map's fog, so it stays sharp at " ..
		"distances where everything else fades out.",

	[ "$nolod" ] =
		"Stops the engine swapping in a lower-resolution version of the " ..
		"texture at a distance.",

	[ "$decal" ] =
		"Treats the material as a decal, meant to be laid over another surface.",

	[ "$reflectivity" ] =
		"How much light this surface bounces onto its neighbours. Only used " ..
		"when a map is compiled, so it does nothing at runtime.",

	------------------------------------------------------------- eyes
	[ "$iris" ] =
		"The iris image for an eye. On the EyeRefract shader this takes the " ..
		"place of $basetexture.",

	[ "$eyeballradius" ] =
		"How curved the eyeball is. Larger values bulge the iris outwards and " ..
		"exaggerate the refraction; smaller flattens it.",

	[ "$dilation" ] =
		"Pupil size. 0.5 is neutral, lower contracts, higher dilates.",

	[ "$glossiness" ] =
		"How wet the eye looks - the strength of the highlight on the cornea.",

	[ "$parallaxstrength" ] =
		"How much the iris appears to shift beneath the cornea as the head " ..
		"turns. This is what sells an eye as having depth.",

	[ "$ambientocclcolor" ] =
		"The colour of the shading where the eyeball meets the socket, which " ..
		"stops it looking like a ball stuck to the face.",

	----------------------------------------------------------- tree sway
	[ "$treesway" ] =
		"Makes the whole model bend in the wind. 1 sways it around its base " ..
		"like a tree trunk; 2 sways each vertex independently, which suits " ..
		"grass and leaves.",
}

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

--- Long-form help for a parameter, falling back to its database description.
--- Returns the body text and a short "Type / default / needs" line.
function AdvMat.GetHelp( shader, key )
	local def  = AdvMat.GetParamDef( shader, key )
	local body = AdvMat.HELP[ key ]
	local translated = AdvMat.I18N and AdvMat.I18N.language ~= "en"

	if translated then
		local catalogue = AdvMat.HELP_I18N
		local locale = catalogue and catalogue[ AdvMat.I18N.language ]
		body = locale and locale[ key ]
		if not body or body == "" then
			body = AdvMat.LocalizedParamDescription( shader, def or { name = key } )
		end
	elseif not body or body == "" then
		body = ( def and def.description ~= "" and def.description )
			or LocalHelp( "help.none" )
	end

	--------------------------------------------------------------- facts
	local TYPE_NAMES = {
		bool      = LocalHelp( "help.bool" ),
		int       = LocalHelp( "help.int" ),
		float     = LocalHelp( "help.float" ),
		color     = LocalHelp( "help.color" ),
		vector2   = LocalHelp( "help.vector2" ),
		vector3   = LocalHelp( "help.vector3" ),
		vector4   = LocalHelp( "help.vector4" ),
		texture   = LocalHelp( "help.texture" ),
		string    = LocalHelp( "help.text" ),
		transform = LocalHelp( "help.transform" ),
		matrix    = LocalHelp( "help.transform" ),
	}

	local facts = { TYPE_NAMES[ def and def.type ] or LocalHelp( "help.value" ) }

	if def then
		if def.default and def.default ~= "" then
			facts[ #facts + 1 ] = LocalHelp( "help.default", { value = def.default } )
		end

		if def.min and def.max then
			facts[ #facts + 1 ] = LocalHelp( "help.range", {
				min = AdvMat.NumToString( def.min ), max = AdvMat.NumToString( def.max ),
			} )
		end

		if def.requires and def.requires ~= "" then
			facts[ #facts + 1 ] = LocalHelp( "help.needs", { value = def.requires } )
		end

		if def.compileTime then
			facts[ #facts + 1 ] = LocalHelp( "help.rebuild" )
		end
	end

	return body, table.concat( facts, "   /   " )
end

--- The extension database contains hundreds of shader-specific parameters.
--- For a non-English client, never fall through to an English description:
--- uncommon entries receive a precise localised technical synopsis instead.
function AdvMat.LocalizedParamDescription( shader, def )
	def = def or {}
	if not AdvMat.I18N or AdvMat.I18N.language == "en" then
		return def.description or LocalHelp( "help.none" )
	end

	return AdvMat.L( "help.generic", {
		name = def.name or "?",
		group = AdvMat.LText( def.group or AdvMat.G.MISC ),
	} )
end
