--[[---------------------------------------------------------------------------
	Advanced Material Editor - shader parameter database

	Every VMT parameter the editor knows how to present, grouped by what it
	does, following the Valve Developer Community documentation for each
	shader. Parameters the database does not know about are still editable as
	raw VMT text, so nothing is ever locked out.

	compileTime = true marks a shader COMBO parameter. Adding or removing one
	changes which shader permutation the engine compiles, which is why the
	editor rebuilds the whole material rather than poking values into the live
	one. See cl_50_apply.lua.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

---------------------------------------------------------------------------
-- Group ordering
---------------------------------------------------------------------------
local G = {
	BASE      = "Base texture",
	TRANS     = "Transparency",
	TINT      = "Colour and tint",
	BUMP      = "Bump / normal map",
	PHONG     = "Phong (specular highlight)",
	RIM       = "Rim light",
	ENV       = "Reflections (cube map)",
	ILLUM     = "Self illumination",
	DETAIL    = "Detail texture",
	LIGHT     = "Lighting",
	XFORM     = "Texture transform",
	EMISSIVE  = "Emissive blend (scrolling glow)",
	DISTALPHA = "Distance alpha (sharp edges)",
	SWAY      = "Tree sway",
	EYE       = "Eye",
	WRINKLE   = "Wrinkle maps (flex driven)",
	SHEEN     = "Sheen (killstreak pass)",
	CLOAK     = "Cloak (refraction pass)",
	FLESH     = "Flesh interior",
	REFRACT   = "Refraction",
	WATER     = "Water",
	BLEND     = "Texture blending",
	FLAGS     = "Render flags",
	COMPILE   = "Compile-time flags",
	MISC      = "Misc",
	OTHER     = "Other parameters on this material",
}

AdvMat.G = G

local GROUP_ORDER = {
	G.BASE, G.TINT, G.TRANS, G.BUMP, G.PHONG, G.RIM, G.ENV, G.ILLUM,
	G.DETAIL, G.LIGHT, G.WRINKLE, G.EMISSIVE, G.SHEEN, G.CLOAK, G.FLESH,
	G.EYE, G.REFRACT, G.WATER, G.BLEND, G.DISTALPHA, G.SWAY, G.XFORM,
	G.FLAGS, G.COMPILE, G.MISC, G.OTHER,
}

local GROUP_RANK = {}
for i, name in ipairs( GROUP_ORDER ) do GROUP_RANK[ name ] = i end

function AdvMat.GroupOrder( name ) return GROUP_RANK[ name ] or 999 end

local OPEN_BY_DEFAULT = {
	[ G.BASE ]  = true,
	[ G.BUMP ]  = true,
	[ G.PHONG ] = true,
	[ G.OTHER ] = true,
}

function AdvMat.GroupStartsOpen( name ) return OPEN_BY_DEFAULT[ name ] == true end

---------------------------------------------------------------------------
-- Parameter helper
---------------------------------------------------------------------------
local function P( name, ptype, group, default, min, max, desc, requires, combo )
	return {
		name        = name,
		type        = ptype,
		group       = group,
		default     = default or "",
		min         = min,
		max         = max,
		description = desc or "",
		requires    = requires or "",
		compileTime = combo == true,
	}
end

---------------------------------------------------------------------------
-- Reusable blocks
---------------------------------------------------------------------------

local BASE = {
	P( "$basetexture", "texture", G.BASE, "", nil, nil,
		"Albedo / diffuse texture. Its alpha channel feeds translucency, phong masks and env map masks." ),
	P( "$frame", "int", G.BASE, "0", 0, 64,
		"Starting frame for an animated $basetexture." ),
	P( "$model", "bool", G.BASE, "1", nil, nil,
		"Marks the material as a model material. Required on anything drawn on a .mdl." , nil, true ),
	P( "$surfaceprop", "string", G.BASE, "", nil, nil,
		"Physical surface property, e.g. metal, flesh, glass." ),
}

local TINT = {
	P( "$color2", "color", G.TINT, "[1 1 1]", nil, nil,
		"Multiplies the base texture. Works correctly with lighting; prefer this over $color on models." ),
	P( "$color", "color", G.TINT, "[1 1 1]", nil, nil,
		"Older colour tint. Applied before lighting, so it can wash out. $color2 is usually what you want." ),
	P( "$blendtintbybasealpha", "bool", G.TINT, "0", nil, nil,
		"Tint only where the base texture alpha is white, so team colours do not stain the whole model.",
		"$color2", true ),
	P( "$blendtintcoloroverbase", "float", G.TINT, "0", 0, 1,
		"0 tints the base texture, 1 replaces it outright.", "$blendtintbybasealpha" ),
	P( "$desaturatewithbasealpha", "float", G.TINT, "0", 0, 1,
		"Desaturates the base texture using its own alpha as the mask." ),
}

local TRANSPARENCY = {
	P( "$translucent", "bool", G.TRANS, "0", nil, nil,
		"Full alpha blending using the base texture alpha. Sorts per model, so it can render out of order.",
		nil, true ),
	P( "$alphatest", "bool", G.TRANS, "0", nil, nil,
		"Cheap 1-bit transparency. Much better sorting than $translucent; use it for hair, leaves, grates.",
		nil, true ),
	P( "$alphatestreference", "float", G.TRANS, "0.5", 0, 1,
		"Alpha cutoff for $alphatest. Lower keeps more of the texture.", "$alphatest" ),
	P( "$allowalphatocoverage", "bool", G.TRANS, "0", nil, nil,
		"Anti-aliases the $alphatest cutoff edge when MSAA is on.", "$alphatest", true ),
	P( "$additive", "bool", G.TRANS, "0", nil, nil,
		"Adds the material to whatever is behind it. Black becomes invisible.", nil, true ),
	P( "$alpha", "float", G.TRANS, "1", 0, 1,
		"Uniform opacity multiplier for the whole material." ),
	P( "$nocull", "bool", G.TRANS, "0", nil, nil,
		"Draw back faces as well as front faces. Doubles the fill cost." ),
	P( "$vertexalpha", "bool", G.TRANS, "0", nil, nil,
		"Use the mesh's vertex alpha for transparency.", nil, true ),
	P( "$vertexcolor", "bool", G.TRANS, "0", nil, nil,
		"Multiply by the mesh's vertex colour.", nil, true ),
}

local BUMP = {
	P( "$bumpmap", "texture", G.BUMP, "", nil, nil,
		"Tangent-space normal map. Its alpha is the default phong and env map mask.", nil, true ),
	P( "$bumpframe", "int", G.BUMP, "0", 0, 64,
		"Starting frame for an animated normal map.", "$bumpmap" ),
	P( "$bumptransform", "string", G.BUMP, "center .5 .5 scale 1 1 rotate 0 translate 0 0", nil, nil,
		"Scale / rotate / scroll the normal map independently of the base texture.", "$bumpmap" ),
	P( "$ssbump", "bool", G.BUMP, "0", nil, nil,
		"The normal map is a self-shadowing bump map rather than a standard tangent-space normal map.",
		"$bumpmap", true ),
	P( "$normalmapalphaenvmapmask", "bool", G.BUMP, "0", nil, nil,
		"Use the normal map alpha as the cube map reflection mask.", "$bumpmap", true ),
}

local PHONG = {
	P( "$phong", "bool", G.PHONG, "0", nil, nil,
		"Enables per-pixel specular. Needs a $bumpmap; the normal map alpha is the default mask.",
		"$bumpmap", true ),
	P( "$phongboost", "float", G.PHONG, "1", 0, 40,
		"Strength multiplier for the highlight. Skin sits near 1-2, wet plastic 5-20.", "$phong" ),
	P( "$phongexponent", "float", G.PHONG, "5", 1, 150,
		"Highlight tightness. Low is broad and soft, high is a small sharp glint.", "$phong" ),
	P( "$phongexponenttexture", "texture", G.PHONG, "", nil, nil,
		"Per-pixel exponent map. Red = exponent, green = albedo tint amount, alpha = rim mask. Blue is unused.",
		"$phong", true ),
	P( "$phongexponentfactor", "float", G.PHONG, "", 1, 256,
		"Scales the values read out of $phongexponenttexture.", "$phongexponenttexture" ),
	P( "$phongalbedotint", "bool", G.PHONG, "0", nil, nil,
		"Tint the highlight by the base texture colour, using the green channel of the exponent map.",
		"$phongexponenttexture", true ),
	P( "$phongalbedoboost", "float", G.PHONG, "1", 0, 15,
		"Extra multiplier on the albedo-tinted part of the highlight.", "$phongalbedotint" ),
	P( "$phongtint", "color", G.PHONG, "[1 1 1]", nil, nil,
		"Colours the highlight. Ignored where $phongalbedotint takes over.", "$phong" ),
	P( "$phongfresnelranges", "vector3", G.PHONG, "[0 0.5 1]", nil, nil,
		"Highlight strength head-on / at glancing angles / at the silhouette. [1 1 1] disables fresnel.",
		"$phong" ),
	P( "$phongwarptexture", "texture", G.PHONG, "", nil, nil,
		"2D lookup that remaps the highlight, used for iridescent and anisotropic looks.", "$phong", true ),
	P( "$phongdisablehalflambert", "bool", G.PHONG, "0", nil, nil,
		"Stop $halflambert from also softening the specular term.", "$phong" ),
	P( "$basemapalphaphongmask", "bool", G.PHONG, "0", nil, nil,
		"Take the phong mask from the base texture alpha instead of the normal map alpha.",
		"$phong", true ),
	P( "$basemapluminancephongmask", "bool", G.PHONG, "0", nil, nil,
		"Use the base texture's brightness as the phong mask. Does not work in Garry's Mod.", "$phong", true ),
	P( "$invertphongmask", "bool", G.PHONG, "0", nil, nil,
		"Named for the phong mask, but in Garry's Mod it inverts the $envmap mask instead.", "$phong" ),
	P( "$phongmaskcontrastbrightness", "vector2", G.PHONG, "[1 0]", nil, nil,
		"Contrast and brightness applied to the phong mask before use. Brush shaders only; not read on a model.", "$phong" ),
}

local RIM = {
	P( "$rimlight", "bool", G.RIM, "0", nil, nil,
		"Adds a light wrap around the silhouette, driven by ambient light. Requires $phong.",
		"$phong", true ),
	P( "$rimlightexponent", "float", G.RIM, "4", 1, 40,
		"How tight the rim band is. Higher hugs the silhouette more closely.", "$rimlight" ),
	P( "$rimlightboost", "float", G.RIM, "1", 0, 20,
		"Rim light brightness.", "$rimlight" ),
	P( "$rimmask", "bool", G.RIM, "0", nil, nil,
		"Mask the rim light with the ALPHA channel of $phongexponenttexture.",
		"$phongexponenttexture", true ),
}

local ENVMAP = {
	P( "$envmap", "texture", G.ENV, "", nil, nil,
		"Cube map reflection. Use env_cubemap to pick up the nearest map cubemap.", nil, true ),
	P( "$envmaptint", "color", G.ENV, "[1 1 1]", nil, nil,
		"Reflection strength and colour. Values above 1 are allowed.", "$envmap" ),
	P( "$envmapmask", "texture", G.ENV, "", nil, nil,
		"Greyscale mask deciding where the reflection shows.", "$envmap", true ),
	P( "$envmapmaskframe", "int", G.ENV, "0", 0, 64,
		"Starting frame for an animated env map mask.", "$envmapmask" ),
	P( "$envmapmasktransform", "string", G.ENV, "center .5 .5 scale 1 1 rotate 0 translate 0 0", nil, nil,
		"Scale / rotate / scroll the env map mask.", "$envmapmask" ),
	P( "$basealphaenvmapmask", "bool", G.ENV, "0", nil, nil,
		"Use the base texture alpha as the reflection mask. Cannot be combined with $translucent.",
		"$envmap", true ),
	P( "$envmapcontrast", "float", G.ENV, "0", 0, 1,
		"0 leaves the cube map alone, 1 squares it, which darkens everything but the highlights.",
		"$envmap" ),
	P( "$envmapsaturation", "color", G.ENV, "[1 1 1]", nil, nil,
		"Per-channel reflection saturation. 0 is greyscale, 1 keeps the full colour. A single number also works.",
		"$envmap" ),
	P( "$envmapframe", "int", G.ENV, "0", 0, 64,
		"Starting frame for an animated cube map.", "$envmap" ),
	P( "$envmapfresnel", "float", G.ENV, "0", 0, 1,
		"Fades the reflection in towards glancing angles, the way real surfaces behave.", "$envmap" ),
	P( "$envmaplightscale", "float", G.ENV, "0", 0, 1,
		"Dims the reflection in shadow so it does not glow in dark rooms.", "$envmap" ),
	P( "$envmaplightscaleminmax", "vector2", G.ENV, "[0 1]", nil, nil,
		"Light range over which $envmaplightscale ramps.", "$envmaplightscale" ),
	P( "$envmapanisotropy", "bool", G.ENV, "0", nil, nil,
		"Stretch the reflection along the surface, for brushed metal.", "$envmap", true ),
	P( "$envmapanisotropyscale", "float", G.ENV, "1", 0, 1,
		"How far the anisotropic reflection stretches.", "$envmapanisotropy" ),
	P( "$fresnelreflection", "float", G.ENV, "1", 0, 1,
		"Older fresnel control for reflections. 1 is uniform, lower fades head-on reflections.", "$envmap" ),
}

local SELFILLUM = {
	P( "$selfillum", "bool", G.ILLUM, "0", nil, nil,
		"Makes parts of the material ignore lighting. Masked by the base texture alpha by default.",
		nil, true ),
	P( "$selfillummask", "texture", G.ILLUM, "", nil, nil,
		"Dedicated glow mask, so the base texture alpha stays free for transparency.",
		"$selfillum", true ),
	P( "$selfillumtint", "color", G.ILLUM, "[1 1 1]", nil, nil,
		"Colours the glowing areas. Values above 1 push it into bloom.", "$selfillum" ),
	P( "$selfillumfresnel", "bool", G.ILLUM, "0", nil, nil,
		"Vary the glow by viewing angle, useful for screens and eyes.", "$selfillum", true ),
	P( "$selfillumfresnelminmaxexp", "vector3", G.ILLUM, "[0 1 1]", nil, nil,
		"Minimum, maximum and exponent for the self-illum fresnel ramp.", "$selfillumfresnel" ),
	P( "$selfillum_envmapmask_alpha", "bool", G.ILLUM, "0", nil, nil,
		"Take the glow mask from the env map mask alpha.", "$selfillum", true ),
}

local DETAIL = {
	P( "$detail", "texture", G.DETAIL, "", nil, nil,
		"Second texture tiled over the base to add close-up grain or decals.", nil, true ),
	P( "$detailscale", "float", G.DETAIL, "4", 0.1, 64,
		"How many times the detail texture tiles across the base texture.", "$detail" ),
	P( "$detailblendfactor", "float", G.DETAIL, "1", 0, 10,
		"How strongly the detail texture shows through.", "$detail" ),
	P( "$detailblendmode", "int", G.DETAIL, "0", 0, 12,
		"0 multiply, 1 additive, 3 translucent, 7 mod2x, 12 multiply. See the wiki for the full list.",
		"$detail", true ),
	P( "$detailtint", "color", G.DETAIL, "[1 1 1]", nil, nil,
		"Tints the detail texture.", "$detail" ),
	P( "$detailframe", "int", G.DETAIL, "0", 0, 64,
		"Starting frame for an animated detail texture.", "$detail" ),
	P( "$detailtexturetransform", "string", G.DETAIL, "center .5 .5 scale 1 1 rotate 0 translate 0 0", nil, nil,
		"Scale / rotate / scroll the detail texture.", "$detail" ),
}

local LIGHTING = {
	P( "$halflambert", "bool", G.LIGHT, "0", nil, nil,
		"Softer, flatter diffuse falloff. Standard on Half-Life 2 characters and on most anime-style models.",
		nil, true ),
	P( "$lightwarptexture", "texture", G.LIGHT, "", nil, nil,
		"1D gradient that remaps diffuse lighting. This is the parameter cel-shaded looks are built on.",
		nil, true ),
	P( "$ambientocclusion", "float", G.LIGHT, "0", 0, 1,
		"Strength of baked ambient occlusion." ),
	P( "$notint", "bool", G.LIGHT, "0", nil, nil,
		"Ignore the entity colour set by Lua or by the colour tool." ),
	P( "$receiveflashlight", "bool", G.LIGHT, "0", nil, nil,
		"Let the flashlight and projected textures light this material even when translucent." ),
	P( "$singlepassflashlight", "bool", G.LIGHT, "0", nil, nil,
		"Cheaper single-pass flashlight handling." ),
	P( "$nodecal", "bool", G.LIGHT, "0", nil, nil,
		"Bullet holes and blood decals will not stick to this material." ),
}

local XFORM = {
	P( "$basetexturetransform", "string", G.XFORM, "center .5 .5 scale 1 1 rotate 0 translate 0 0", nil, nil,
		"Scale, rotate and scroll the base texture. Syntax: center X Y scale X Y rotate D translate X Y." ),
}

local FLAGS = {
	P( "$nolod", "bool", G.FLAGS, "0", nil, nil,
		"Never swap this material for a lower detail version." ),
	P( "$ignorez", "bool", G.FLAGS, "0", nil, nil,
		"Draw through walls. Everything using this material becomes an x-ray overlay." ),
	P( "$znearer", "bool", G.FLAGS, "0", nil, nil,
		"Bias the depth test so this draws in front of coincident surfaces." ),
	P( "$wireframe", "bool", G.FLAGS, "0", nil, nil,
		"Render only the edges of the triangles." ),
	P( "$flat", "bool", G.FLAGS, "0", nil, nil,
		"Skip lighting entirely and draw the texture flat." ),
	P( "$nofog", "bool", G.FLAGS, "0", nil, nil,
		"Exempt this material from world fog." ),
	P( "$no_fullbright", "bool", G.FLAGS, "0", nil, nil,
		"Keep normal lighting even when mat_fullbright is on." ),
	P( "$decal", "bool", G.FLAGS, "0", nil, nil,
		"Treat the material as a decal." ),
	P( "$opaquetexture", "bool", G.FLAGS, "0", nil, nil,
		"Tell the engine the texture has no transparent pixels, which helps sorting." ),
	P( "$reflectivity", "color", G.FLAGS, "", nil, nil,
		"Overrides how much light the surface bounces during radiosity compiles." ),
}

local DISTALPHA = {
	P( "$distancealpha", "bool", G.DISTALPHA, "0", nil, nil,
		"Treat the alpha channel as a signed distance field, so edges stay razor sharp at any zoom.",
		nil, true ),
	P( "$softedges", "bool", G.DISTALPHA, "0", nil, nil,
		"Anti-alias the distance-field edge.", "$distancealpha" ),
	P( "$edgesoftnessstart", "float", G.DISTALPHA, "0.6", 0, 1,
		"Where the soft edge begins.", "$softedges" ),
	P( "$edgesoftnessend", "float", G.DISTALPHA, "0.5", 0, 1,
		"Where the soft edge finishes.", "$softedges" ),
	P( "$outline", "bool", G.DISTALPHA, "0", nil, nil,
		"Draw an outline around the distance-field shape.", "$distancealpha" ),
	P( "$outlinecolor", "color", G.DISTALPHA, "[0 0 0]", nil, nil, "Outline colour.", "$outline" ),
	P( "$outlinealpha", "float", G.DISTALPHA, "1", 0, 1, "Outline opacity.", "$outline" ),
	P( "$outlinestart0", "float", G.DISTALPHA, "0.0", 0, 1, "Outer edge of the outline fade-in.", "$outline" ),
	P( "$outlinestart1", "float", G.DISTALPHA, "0.0", 0, 1, "Inner edge of the outline fade-in.", "$outline" ),
	P( "$outlineend0", "float", G.DISTALPHA, "0.0", 0, 1, "Inner edge of the outline fade-out.", "$outline" ),
	P( "$outlineend1", "float", G.DISTALPHA, "0.0", 0, 1, "Outer edge of the outline fade-out.", "$outline" ),
}

local EMISSIVE = {
	P( "$emissiveblendenabled", "bool", G.EMISSIVE, "0", nil, nil,
		"Scrolling emissive layer, as used on the Team Fortress 2 Australium weapons.", nil, true ),
	P( "$emissiveblendbasetexture", "texture", G.EMISSIVE, "", nil, nil,
		"Texture that is made to glow.", "$emissiveblendenabled" ),
	P( "$emissiveblendtexture", "texture", G.EMISSIVE, "", nil, nil,
		"Mask deciding where the glow appears.", "$emissiveblendenabled" ),
	P( "$emissiveblendflowtexture", "texture", G.EMISSIVE, "", nil, nil,
		"Flow map that distorts the scrolling glow.", "$emissiveblendenabled" ),
	P( "$emissiveblendtint", "color", G.EMISSIVE, "[1 1 1]", nil, nil,
		"Glow colour.", "$emissiveblendenabled" ),
	P( "$emissiveblendstrength", "float", G.EMISSIVE, "1", 0, 10,
		"Glow brightness.", "$emissiveblendenabled" ),
	P( "$emissiveblendscrollvector", "vector2", G.EMISSIVE, "[0.11 0.124]", nil, nil,
		"Scroll speed and direction of the glow.", "$emissiveblendenabled" ),
	P( "$time", "float", G.EMISSIVE, "0", 0, 100,
		"Animation time driver. Usually fed by a proxy rather than set by hand." ),
}

local SWAY = {
	P( "$treesway", "int", G.SWAY, "0", 0, 2,
		"0 off, 1 sway around the entity origin, 2 sway around each vertex.", nil, true ),
	P( "$treeswayheight", "float", G.SWAY, "1000", 0, 4000, "Height the sway is scaled against.", "$treesway" ),
	P( "$treeswaystartheight", "float", G.SWAY, "0.1", 0, 1, "Fraction of the height where sway begins.", "$treesway" ),
	P( "$treeswayradius", "float", G.SWAY, "300", 0, 2000, "Radius the sway is scaled against.", "$treesway" ),
	P( "$treeswaystartradius", "float", G.SWAY, "0.2", 0, 1, "Fraction of the radius where sway begins.", "$treesway" ),
	P( "$treeswayspeed", "float", G.SWAY, "1", 0, 10, "Overall sway speed.", "$treesway" ),
	P( "$treeswaystrength", "float", G.SWAY, "10", 0, 100, "Overall sway distance.", "$treesway" ),
	P( "$treeswayscrumblespeed", "float", G.SWAY, "5", 0, 20, "Speed of the fine leaf flutter.", "$treesway" ),
	P( "$treeswayscrumblestrength", "float", G.SWAY, "10", 0, 100, "Strength of the fine leaf flutter.", "$treesway" ),
	P( "$treeswayscrumblefrequency", "float", G.SWAY, "12", 0, 60, "Frequency of the fine leaf flutter.", "$treesway" ),
	P( "$treeswayfalloffexp", "float", G.SWAY, "1.5", 0, 8, "Falloff curve of the main sway.", "$treesway" ),
	P( "$treeswayscrumblefalloffexp", "float", G.SWAY, "1", 0, 8, "Falloff curve of the flutter.", "$treesway" ),
	P( "$treeswayspeedlerpstart", "float", G.SWAY, "3", 0, 20, "Wind speed where the fast sway starts blending in.", "$treesway" ),
	P( "$treeswayspeedlerpend", "float", G.SWAY, "6", 0, 20, "Wind speed where the fast sway is fully blended in.", "$treesway" ),
	P( "$treeswayspeedhighwindmultiplier", "float", G.SWAY, "2", 0, 10, "Extra speed applied in high wind.", "$treesway" ),
	P( "$treeswaystatic", "bool", G.SWAY, "0", nil, nil, "Sway without needing a wind entity.", "$treesway" ),
}

---------------------------------------------------------------------------
-- Shader definitions
---------------------------------------------------------------------------
AdvMat.Shaders    = {}
AdvMat.ParamIndex = {}

local function DefineShader( name, blocks )
	local list, index = {}, {}

	for _, block in ipairs( blocks ) do
		for _, def in ipairs( block ) do
			if not index[ def.name ] then
				list[ #list + 1 ]  = def
				index[ def.name ]  = def
			end
		end
	end

	AdvMat.Shaders[ name ]    = list
	AdvMat.ParamIndex[ name ] = index
end

AdvMat.DefineShader = DefineShader
AdvMat.Param        = P

--- Append parameters to an already defined shader. Never replaces an existing
--- entry, so the hand-written core above always wins.
function AdvMat.ExtendShader( name, block )
	local list  = AdvMat.Shaders[ name ]
	local index = AdvMat.ParamIndex[ name ]
	if not list or not index then return end

	for _, def in ipairs( block ) do
		if not index[ def.name ] then
			list[ #list + 1 ] = def
			index[ def.name ] = def
		end
	end
end

---------------------------------------------------------------- VertexLitGeneric
DefineShader( "VertexLitGeneric", {
	BASE, TINT, TRANSPARENCY, BUMP, PHONG, RIM, ENVMAP, SELFILLUM,
	DETAIL, LIGHTING, EMISSIVE, DISTALPHA, SWAY, XFORM, FLAGS,
} )

---------------------------------------------------------------- UnlitGeneric
DefineShader( "UnlitGeneric", {
	BASE, TINT, TRANSPARENCY, ENVMAP, DETAIL, DISTALPHA, XFORM, FLAGS,
	{
		P( "$nofog", "bool", G.FLAGS, "0", nil, nil, "Exempt this material from world fog." ),
	},
} )

---------------------------------------------------------------- LightmappedGeneric
DefineShader( "LightmappedGeneric", {
	BASE, TINT, TRANSPARENCY, BUMP, ENVMAP, SELFILLUM, DETAIL, XFORM, FLAGS,
	{
		P( "$basetexture2", "texture", G.BLEND, "", nil, nil,
			"Second texture blended in by vertex alpha on displacements.", nil, true ),
		P( "$bumpmap2", "texture", G.BLEND, "", nil, nil,
			"Normal map for the second blend layer.", "$basetexture2", true ),
		P( "$blendmodulatetexture", "texture", G.BLEND, "", nil, nil,
			"Controls where the two layers meet. Red is the blend mask, green the transition width.",
			"$basetexture2", true ),
		P( "$seamless_scale", "float", G.BLEND, "0", 0, 4,
			"Projects the texture from world space to hide UV seams. 0 disables it." ),
		P( "$parallaxmap", "texture", G.BUMP, "", nil, nil,
			"Height map used for parallax offset.", "$bumpmap", true ),
		P( "$parallaxmapscale", "float", G.BUMP, "0.02", 0, 0.5,
			"How far the parallax effect displaces the texture.", "$parallaxmap" ),
		P( "%tooltexture", "texture", G.COMPILE, "", nil, nil,
			"Thumbnail shown in Hammer's material browser." ),
		P( "%keywords", "string", G.COMPILE, "", nil, nil, "Hammer browser tags." ),
		P( "%compilenolight", "bool", G.COMPILE, "0", nil, nil, "Skip lightmapping this surface." ),
		P( "%compilenodraw", "bool", G.COMPILE, "0", nil, nil, "Remove the surface at compile time." ),
	},
} )

---------------------------------------------------------------- WorldVertexTransition
DefineShader( "WorldVertexTransition", {
	BASE, TINT, TRANSPARENCY, BUMP, ENVMAP, DETAIL, XFORM, FLAGS,
	{
		P( "$basetexture2", "texture", G.BLEND, "", nil, nil,
			"Second blend layer, mixed in by vertex alpha.", nil, true ),
		P( "$bumpmap2", "texture", G.BLEND, "", nil, nil, "Normal map for the second layer.",
			"$basetexture2", true ),
		P( "$blendmodulatetexture", "texture", G.BLEND, "", nil, nil,
			"Red channel is the blend mask, green the transition width.", "$basetexture2", true ),
		P( "$surfaceprop2", "string", G.BLEND, "", nil, nil, "Surface property of the second layer." ),
	},
} )

---------------------------------------------------------------- EyeRefract
DefineShader( "EyeRefract", {
	{
		P( "$iris", "texture", G.EYE, "", nil, nil,
			"Iris texture. On EyeRefract this replaces $basetexture.", nil, true ),
		P( "$irisframe", "int", G.EYE, "0", 0, 64, "Starting frame of an animated iris.", "$iris" ),
		P( "$corneatexture", "texture", G.EYE, "", nil, nil,
			"Normal map of the corneal bulge, which produces the refraction.", nil, true ),
		P( "$ambientoccltexture", "texture", G.EYE, "", nil, nil,
			"Ambient occlusion around the eyeball, so it sits properly in the socket." ),
		P( "$ambientocclcolor", "color", G.EYE, "[0.33 0.33 0.33]", nil, nil,
			"Colour of the eyeball ambient occlusion.", "$ambientoccltexture" ),
		P( "$eyeballradius", "float", G.EYE, "0.5", 0.1, 1.5,
			"Radius of the eyeball sphere. Larger values bulge the iris outwards." ),
		P( "$dilation", "float", G.EYE, "0.5", 0, 1, "Pupil dilation. 0.5 is neutral." ),
		P( "$glossiness", "float", G.EYE, "1", 0, 4, "Strength of the wet highlight on the cornea." ),
		P( "$parallaxstrength", "float", G.EYE, "0.25", 0, 1,
			"How much the iris shifts under the cornea as the view angle changes." ),
		P( "$corneabumpstrength", "float", G.EYE, "1", 0, 4,
			"Strength of the corneal normal map.", "$corneatexture" ),
		P( "$raytracesphere", "bool", G.EYE, "1", nil, nil,
			"Ray trace against the eyeball sphere for correct refraction.", nil, true ),
		P( "$spheretexkillcombo", "bool", G.EYE, "1", nil, nil,
			"Discard pixels that fall outside the eyeball sphere.", "$raytracesphere", true ),
		P( "$halflambert", "bool", G.EYE, "0", nil, nil, "Softer diffuse falloff on the eye.", nil, true ),
		P( "$lightwarptexture", "texture", G.EYE, "", nil, nil,
			"1D lighting ramp for the eye.", nil, true ),
		P( "$intro", "bool", G.EYE, "0", nil, nil, "Half-Life 2 intro camera effect." ),
	},
	ENVMAP, TRANSPARENCY, FLAGS,
} )

---------------------------------------------------------------- Eyes
DefineShader( "Eyes", {
	{
		P( "$iris", "texture", G.EYE, "", nil, nil, "Iris texture drawn over the sclera.", nil, true ),
		P( "$irisframe", "int", G.EYE, "0", 0, 64, "Starting frame of an animated iris.", "$iris" ),
	},
	BASE, TINT, TRANSPARENCY, LIGHTING, FLAGS,
} )

---------------------------------------------------------------- Refract
DefineShader( "Refract", {
	{
		P( "$normalmap", "texture", G.REFRACT, "", nil, nil,
			"Normal map that bends whatever is behind the surface.", nil, true ),
		P( "$refractamount", "float", G.REFRACT, "0.1", -1, 1,
			"How far the background is displaced. Negative inverts the distortion." ),
		P( "$refracttint", "color", G.REFRACT, "[1 1 1]", nil, nil, "Tints the refracted image." ),
		P( "$refracttinttexture", "texture", G.REFRACT, "", nil, nil,
			"Per-pixel tint for the refracted image." ),
		P( "$bluramount", "int", G.REFRACT, "0", 0, 2,
			"0 none, 1 blurs the refracted image, 2 blurs it more." ),
		P( "$fadeoutonsilhouette", "bool", G.REFRACT, "0", nil, nil,
			"Fade the refraction out towards the silhouette of the model." ),
		P( "$scale", "vector2", G.REFRACT, "[1 1]", nil, nil, "Scales the refraction offsets." ),
		P( "$nowritez", "bool", G.REFRACT, "0", nil, nil, "Do not write to the depth buffer." ),
	},
	BASE, TINT, TRANSPARENCY, BUMP, ENVMAP, XFORM, FLAGS,
} )

---------------------------------------------------------------- Water
DefineShader( "Water", {
	{
		P( "$normalmap", "texture", G.WATER, "", nil, nil, "Surface ripple normal map.", nil, true ),
		P( "$refracttexture", "texture", G.WATER, "_rt_WaterRefraction", nil, nil,
			"Render target holding what is under the water.", nil, true ),
		P( "$refractamount", "float", G.WATER, "0.3", 0, 1, "Strength of the underwater distortion." ),
		P( "$refracttint", "color", G.WATER, "[1 1 1]", nil, nil, "Underwater colour." ),
		P( "$reflecttexture", "texture", G.WATER, "_rt_WaterReflection", nil, nil,
			"Render target holding the reflected world.", nil, true ),
		P( "$reflectamount", "float", G.WATER, "0.3", 0, 1, "Strength of the reflection distortion." ),
		P( "$reflecttint", "color", G.WATER, "[1 1 1]", nil, nil, "Reflection colour." ),
		P( "$reflectentities", "bool", G.WATER, "0", nil, nil,
			"Reflect props and players, not just the world. Expensive." ),
		P( "$scale", "vector2", G.WATER, "[1 1]", nil, nil, "Tiling of the ripple normal map." ),
		P( "$bumpframe", "int", G.WATER, "0", 0, 64, "Starting frame of the animated normal map." ),
		P( "$fogenable", "bool", G.WATER, "1", nil, nil, "Fog the water volume." ),
		P( "$fogcolor", "color", G.WATER, "[0.2 0.3 0.3]", nil, nil, "Underwater fog colour.", "$fogenable" ),
		P( "$fogstart", "float", G.WATER, "0", -1000, 1000, "Depth where the fog begins.", "$fogenable" ),
		P( "$fogend", "float", G.WATER, "200", 0, 4000, "Depth where the fog is fully opaque.", "$fogenable" ),
		P( "$abovewater", "bool", G.WATER, "1", nil, nil, "This material is the surface seen from above." ),
		P( "$flashlighttint", "float", G.WATER, "1", 0, 4, "Flashlight strength on the water." ),
	},
	FLAGS,
} )

---------------------------------------------------------------- Modulate
DefineShader( "Modulate", {
	{
		P( "$mod2x", "bool", G.BASE, "0", nil, nil,
			"Grey is neutral, darker darkens, lighter brightens. Off, the texture simply multiplies." ),
		P( "$writez", "bool", G.BASE, "0", nil, nil, "Write to the depth buffer." ),
	},
	BASE, TINT, TRANSPARENCY, XFORM, FLAGS,
} )

---------------------------------------------------------------- Cable
DefineShader( "Cable", {
	BASE, TINT, TRANSPARENCY, BUMP, XFORM, FLAGS,
	{
	},
} )

---------------------------------------------------------------- Sprite / SpriteCard
DefineShader( "Sprite", {
	BASE, TINT, TRANSPARENCY, XFORM, FLAGS,
	{
		P( "$spriteorientation", "string", G.MISC, "vp_parallel", nil, nil,
			"vp_parallel, vp_parallel_upright, oriented, parallel_upright or vp_parallel_oriented." ),
		P( "$spriteorigin", "vector2", G.MISC, "[0.5 0.5]", nil, nil, "Pivot point of the sprite." ),
	},
} )

DefineShader( "SpriteCard", {
	BASE, TINT, TRANSPARENCY, XFORM, FLAGS,
	{
		P( "$blendframes", "bool", G.MISC, "1", nil, nil, "Cross-fade between animation frames." ),
		P( "$addself", "float", G.MISC, "0", 0, 2, "Add the sprite to itself to brighten it." ),
		P( "$maxsize", "float", G.MISC, "", 0, 1, "Clamp the on-screen size of the sprite." ),
		P( "$minsize", "float", G.MISC, "", 0, 1, "Minimum on-screen size of the sprite." ),
		P( "$depthblend", "bool", G.MISC, "0", nil, nil, "Soften the sprite where it intersects geometry." ),
		P( "$depthblendscale", "float", G.MISC, "50", 0, 500, "Softening distance.", "$depthblend" ),
	},
} )

---------------------------------------------------------------- Wireframe / DebugMode
DefineShader( "Wireframe", { TINT, TRANSPARENCY, FLAGS } )

---------------------------------------------------------------------------
-- Lookup API
---------------------------------------------------------------------------
local SHADER_ORDER = {
	"VertexLitGeneric", "UnlitGeneric", "LightmappedGeneric", "WorldVertexTransition",
	"EyeRefract", "Eyes", "Refract", "Water", "Modulate", "Cable",
	"Sprite", "SpriteCard", "Wireframe",
}

function AdvMat.GetShaderList()
	return table.Copy( SHADER_ORDER )
end

--- Shader names are case insensitive to the engine, and authors write them
--- every possible way - "VertexlitGeneric" and "vertexlitgeneric" are both
--- common in the wild. Everything downstream compares names, so they are
--- folded to the database's spelling first.
local canonical

function AdvMat.CanonicalShader( name )
	if not isstring( name ) or name == "" then return "VertexLitGeneric" end

	if not canonical then
		canonical = {}
		for known in pairs( AdvMat.Shaders ) do
			canonical[ string.lower( known ) ] = known
		end
	end

	return canonical[ string.lower( name ) ] or name
end

--- Ordered parameter definitions for a shader. Unknown shaders fall back to
--- VertexLitGeneric, which is a superset of what most model shaders accept.
function AdvMat.GetShaderParams( shader )
	return AdvMat.Shaders[ AdvMat.CanonicalShader( shader ) ]
		or AdvMat.Shaders[ "VertexLitGeneric" ]
end

-- Name based type guesses, for parameters the database has never heard of.
local TEXTURE_HINTS = { "texture$", "map$", "^%$iris$", "^%$detail$", "^%$envmap$", "^%$normalmap$" }
local BOOL_HINTS    = { "^%$no", "^%$is", "enabled?$", "^%$allow", "^%$disable" }

local function GuessType( key )
	for _, pat in ipairs( TEXTURE_HINTS ) do
		if string.find( key, pat ) then return "texture" end
	end
	for _, pat in ipairs( BOOL_HINTS ) do
		if string.find( key, pat ) then return "bool" end
	end
	return "string"
end

--- Definition for a single parameter. Always returns something: unknown keys
--- get a synthesised definition so they can still be edited as raw VMT text.
function AdvMat.GetParamDef( shader, key )
	local index = AdvMat.ParamIndex[ AdvMat.CanonicalShader( shader ) ]
	if index and index[ key ] then return index[ key ] end

	-- Fall back to any other shader that documents this parameter, so a
	-- material with an unusual shader still gets nice widgets.
	for _, defs in pairs( AdvMat.ParamIndex ) do
		if defs[ key ] then return defs[ key ] end
	end

	return P( key, GuessType( key ), AdvMat.G.OTHER, "", nil, nil,
		"Not in the parameter database. Edited as raw VMT text." )
end
