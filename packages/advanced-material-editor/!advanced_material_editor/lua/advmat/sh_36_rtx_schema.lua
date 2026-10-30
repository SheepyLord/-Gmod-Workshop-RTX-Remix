--[[---------------------------------------------------------------------------
	Advanced Material Editor - RTX Remix profile schema and graph compiler

	This module is deliberately realm-independent.  It describes the data the
	RTX editor owns, validates the small node language exposed by that editor,
	and compiles it to a normalized PBR record.  It does not read vanilla VMT
	parameters, generated-texture recipes, entities, convars, or Remix globals.
	Keeping that boundary here means loading this file cannot alter the vanilla
	editor in any way.

	A compiled texture is either a path or a bake descriptor:

		{ source = "models/example/metal_r", generated = true,
		  ops = { { op = "invert" }, { op = "multiply", value = 0.5 } } }

	The client-side RTX map builder resolves descriptors to concrete image paths
	before passing the result across the versioned native-writer boundary.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.RTX = AdvMat.RTX or {}

local S = {}

AdvMat.RTX.Schema = S
-- Short alias for shared tests and third-party integrations.  Both names
-- point at the same table; no state is copied between them.
AdvMat.RTXSchema = S

S.VERSION = 1

S.LIMITS = {
	NODES       = 64,
	LINKS       = 128,
	HASHES      = 32,
	-- Keep this identical to the bundled native writer's
	-- kMaxTextureOperations.  The Lua boundary must reject an oversized bake
	-- before a profile can be persisted as apparently applicable.
	MAP_OPS     = 4,
	ID_BYTES    = 48,
	LABEL_BYTES = 96,
	PATH_BYTES  = 260,
	DEPTH       = 32,
	RECIPE_DEPTH   = 16,
	RECIPE_ENTRIES = 65536,
	RECIPE_STRING  = 4096,
	RECIPE_KEY     = 128,
}

local TARGET_KINDS = {
	material = true,
	model    = true,
	hash     = true,
}

local MAP_KEYS = {
	albedo                   = true,
	normal                   = true,
	anisotropy               = true,
	roughness                = true,
	metallic                 = true,
	height                   = true,
	emissive                 = true,
	subsurface_transmittance = true,
	subsurface_thickness     = true,
	subsurface_scattering    = true,
	subsurface_radius        = true,
}

local CHANNELS = {
	luminance = true,
	r         = true,
	g         = true,
	b         = true,
	a         = true,
}

-- AperturePBR_Model.mdl exposes exactly two sampler modes.  Anisotropic
-- filtering is a runtime/global policy, not a per-material MDL enum.
local FILTER_MODES = { nearest = true, linear = true }
local WRAP_MODES   = { [ "repeat" ] = true, mirror = true, clamp = true, clip = true }
local NORMAL_ENCODINGS = {
	octahedral       = true,
	tangent_space_ogl = true,
	tangent_space_dx  = true,
}
-- Keep the labels aligned with AperturePBR_Model.mdl's BlendType enum.  The
-- `opaque` value is our sentinel for authoring no blend override.
local BLEND_TYPES  = {
	opaque = true,
	alpha = true,
	alpha_emissive = true,
	reverse_alpha_emissive = true,
	color = true,
	color_emissive = true,
	reverse_color_emissive = true,
	emissive = true,
	multiplicative = true,
	double_multiplicative = true,
}
local ALPHA_TESTS  = {
	none = true,
	never = true,
	less = true,
	equal = true,
	less_equal = true,
	greater = true,
	not_equal = true,
	greater_equal = true,
}

-- Names used by the first UI prototype.  They are accepted at the schema
-- edge, then folded to the compact canonical vocabulary above so saved files
-- and profile hashes never depend on which UI spelling created them.
local NODE_TYPE_ALIASES = {
	material_output = "output_surface",
	source_texture  = "texture",
	scalar          = "value",
}

S.DEFAULT_CONSTANTS = {
	albedo              = { r = 1, g = 1, b = 1 },
	opacity             = 1,
	roughness           = 0.5,
	metallic            = 0,
	emissive_color      = { r = 1, g = 0.1, b = 0.1 },
	emissive_intensity  = 40,
	anisotropy          = 0,
	thin_film_thickness = 200,
	displace_in         = 0.05,
	displace_out        = 0,
	subsurface_transmittance_color = { r = 0.5, g = 0.5, b = 0.5 },
	subsurface_measurement_distance = 0,
	subsurface_single_scattering_albedo = { r = 0.5, g = 0.5, b = 0.5 },
	subsurface_volumetric_anisotropy = 0,
	subsurface_radius       = { r = 0.5, g = 0.5, b = 0.5 },
	subsurface_radius_scale = 1,
	subsurface_max_sample_radius = 16,
}

S.DEFAULT_OPTIONS = {
	filter_mode           = "linear",
	wrap_u                = "repeat",
	wrap_v                = "repeat",
	alpha_is_thin_film    = false,
	use_draw_call_alpha   = true,
	inverted_blend        = false,
	blend_type            = "opaque",
	alpha_test_type       = "none",
	alpha_reference       = 0,
	sprite_sheet_rows     = 1,
	sprite_sheet_columns  = 1,
	sprite_sheet_fps      = 0,
	enable_thin_film      = false,
	enable_emission       = false,
	-- AdvMat maps are external replacement files rather than captured game
	-- textures, so retain the bridge's historical auto-preload behaviour by
	-- default.  The explicit UI flag still lets advanced users opt out.
	preload_textures      = true,
	ignore_material       = false,
	blend_enabled         = false,
	normal_encoding       = "tangent_space_dx",
	subsurface_diffusion_profile = false,
}

-- Socket types are part of the public contract so the node editor can build
-- pins without duplicating the compiler's rules.  "numeric" accepts a scalar
-- or colour.  "dynamic" is resolved from a node's incoming links.
S.NODE_TYPES = {
	output_surface = {
		inputs = {
			albedo              = "color",
			normal              = "normal",
			roughness           = "number",
			metallic            = "number",
			height              = "number",
			emissive            = "color",
			emissive_intensity  = "number",
			opacity             = "number",
			anisotropy          = "number",
			thin_film_thickness = "number",
			displace_in         = "number",
			displace_out        = "number",
			subsurface_transmittance = "color",
			subsurface_thickness = "number",
			subsurface_scattering = "color",
			subsurface_volumetric_anisotropy = "number",
			subsurface_radius = "color",
			subsurface_radius_scale = "number",
			subsurface_max_sample_radius = "number",
		},
		outputs = {},
	},
	texture = {
		inputs  = {},
		outputs = { color = "color", value = "number", normal = "normal" },
	},
	value = {
		inputs  = {},
		outputs = { value = "number" },
	},
	color = {
		inputs  = {},
		outputs = { color = "color" },
	},
	invert = {
		inputs  = { value = "numeric" },
		outputs = { value = "dynamic" },
	},
	multiply = {
		inputs  = { a = "numeric", b = "numeric" },
		outputs = { value = "dynamic" },
	},
	normal_from_height = {
		inputs  = { height = "number" },
		outputs = { normal = "normal" },
	},
}

---------------------------------------------------------------------------
-- Small pure-Lua helpers
---------------------------------------------------------------------------

local function IsTable( value ) return type( value ) == "table" end

local function Trim( value )
	if type( value ) ~= "string" then return "" end
	return ( ( string.gsub( value, "^%s*(.-)%s*$", "%1" ) ) )
end

local function Clamp( value, lo, hi )
	if value < lo then return lo end
	if value > hi then return hi end
	return value
end

local function FiniteNumber( value )
	local number = tonumber( value )
	if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
	return number
end

local function AddError( errors, path, message )
	errors[ #errors + 1 ] = path .. ": " .. message
end

local function CopyColor( color )
	return { r = color.r, g = color.g, b = color.b }
end

local function CopyArray( source )
	local out = {}
	for index, value in ipairs( source or {} ) do out[ index ] = value end
	return out
end

-- Copy a recipe without invoking metamethods or accepting executable values.
-- This fallback is used while the generator modules are not loaded (and by
-- standalone tooling).  Its job is preservation plus a hard memory bound;
-- AdvMat.Gen.Sanitize performs the recipe-kind validation when available.
local function SafeRecipeCopy( raw, path, errors )
	local seen, entries = {}, 0

	local function Copy( value, depth, valuePath )
		local kind = type( value )
		if kind == "nil" or kind == "boolean" then return value, true end
		if kind == "number" then
			if not FiniteNumber( value ) then
				AddError( errors, valuePath, "contains a non-finite recipe number" )
				return nil, false
			end
			return value, true
		end
		if kind == "string" then
			if #value > S.LIMITS.RECIPE_STRING or string.find( value, "[%z\1-\31]" ) then
				AddError( errors, valuePath, "contains an unsafe or over-long recipe string" )
				return nil, false
			end
			return value, true
		end
		if kind ~= "table" then
			AddError( errors, valuePath, "contains a non-JSON recipe value" )
			return nil, false
		end
		if depth >= S.LIMITS.RECIPE_DEPTH then
			AddError( errors, valuePath, "recipe nesting is too deep" )
			return nil, false
		end
		if getmetatable( value ) ~= nil then
			AddError( errors, valuePath, "recipe tables must not have metatables" )
			return nil, false
		end
		if seen[ value ] then
			AddError( errors, valuePath, "recipe contains a cycle" )
			return nil, false
		end

		seen[ value ] = true
		local out = {}
		local key, item = next( value, nil )
		while key ~= nil do
			entries = entries + 1
			if entries > S.LIMITS.RECIPE_ENTRIES then
				seen[ value ] = nil
				AddError( errors, path, "recipe exceeds the entry limit" )
				return nil, false
			end

			local keyKind = type( key )
			if keyKind == "string" then
				if #key > S.LIMITS.RECIPE_KEY or string.find( key, "[%z\1-\31]" ) then
					seen[ value ] = nil
					AddError( errors, valuePath, "contains an unsafe recipe key" )
					return nil, false
				end
			elseif keyKind ~= "number" or not FiniteNumber( key ) or key < 1
				or key ~= math.floor( key ) or key > S.LIMITS.RECIPE_ENTRIES then
				seen[ value ] = nil
				AddError( errors, valuePath, "contains a non-JSON recipe key" )
				return nil, false
			end

			local copy, ok = Copy( item, depth + 1, valuePath .. "." .. tostring( key ) )
			if not ok then seen[ value ] = nil return nil, false end
			out[ key ] = copy
			key, item = next( value, key )
		end
		seen[ value ] = nil
		return out, true
	end

	local copy, ok = Copy( raw, 0, path )
	return ok and copy or nil
end

local function SanitizeRecipe( raw, path, errors )
	if raw == nil then return nil end
	if not IsTable( raw ) then
		AddError( errors, path, "must be a recipe table" )
		return nil
	end

	-- Strip metatables/functions and enforce the size bound *before* calling a
	-- kind sanitizer.  That sanitizer is trusted addon code, but its field
	-- reads must never trigger an untrusted __index from an in-process caller.
	local candidate = SafeRecipeCopy( raw, path, errors )
	if not candidate then return nil end
	local generator = AdvMat and AdvMat.Gen
	if IsTable( generator ) and type( generator.Sanitize ) == "function" then
		local ok, clean = pcall( generator.Sanitize, candidate )
		if not ok then
			AddError( errors, path, "generator sanitizer failed" )
			return nil
		end
		if not IsTable( clean ) then
			AddError( errors, path, "is not a valid generated-texture recipe" )
			return nil
		end
		candidate = clean
	end

	return SafeRecipeCopy( candidate, path, errors )
end

-- Returns the length of a dense JSON-style array.  Named keys, holes, and
-- fractional indices are rejected.  An empty table is a valid empty array.
local function DenseLength( value, cap, path, errors )
	if not IsTable( value ) then
		AddError( errors, path, "must be an array" )
		return nil
	end

	local count, greatest = 0, 0
	for key in pairs( value ) do
		if type( key ) ~= "number" or key < 1 or key ~= math.floor( key ) then
			AddError( errors, path, "must contain only consecutive numeric keys" )
			return nil
		end
		count = count + 1
		if key > greatest then greatest = key end
	end

	if count ~= greatest then
		AddError( errors, path, "must not contain holes" )
		return nil
	end
	if count > cap then
		AddError( errors, path, "exceeds the limit of " .. cap )
		return nil
	end

	return count
end

local function ReadNumber( raw, fallback, lo, hi, path, errors )
	if raw == nil then return fallback end
	local number = FiniteNumber( raw )
	if not number then
		AddError( errors, path, "must be a finite number" )
		return fallback
	end
	return Clamp( number, lo, hi )
end

local function ReadInteger( raw, fallback, lo, hi, path, errors )
	local number = ReadNumber( raw, fallback, lo, hi, path, errors )
	return math.floor( number )
end

local function ReadBoolean( raw, fallback, path, errors )
	if raw == nil then return fallback end
	if raw == true or raw == 1 or raw == "1" or raw == "true" then return true end
	if raw == false or raw == 0 or raw == "0" or raw == "false" then return false end
	AddError( errors, path, "must be a boolean" )
	return fallback
end

local function ReadEnum( raw, fallback, choices, path, errors )
	if raw == nil then return fallback end
	if type( raw ) ~= "string" then
		AddError( errors, path, "must be a string" )
		return fallback
	end
	local value = string.lower( Trim( raw ) )
	if not choices[ value ] then
		AddError( errors, path, "contains an unsupported value" )
		return fallback
	end
	return value
end

local function ReadColor( raw, fallback, lo, hi, path, errors )
	if raw == nil then return CopyColor( fallback ) end
	if not IsTable( raw ) then
		AddError( errors, path, "must be a three-channel colour" )
		return CopyColor( fallback )
	end

	local r = raw.r
	local g = raw.g
	local b = raw.b
	if r == nil then r = raw.x or raw[ 1 ] end
	if g == nil then g = raw.y or raw[ 2 ] end
	if b == nil then b = raw.z or raw[ 3 ] end

	if r == nil or g == nil or b == nil then
		AddError( errors, path, "must provide r, g, and b" )
		return CopyColor( fallback )
	end

	local rr = FiniteNumber( r )
	local gg = FiniteNumber( g )
	local bb = FiniteNumber( b )
	if not rr or not gg or not bb then
		AddError( errors, path, "channels must be finite numbers" )
		return CopyColor( fallback )
	end

	return {
		r = Clamp( rr, lo, hi ),
		g = Clamp( gg, lo, hi ),
		b = Clamp( bb, lo, hi ),
	}
end

local function SafeRelativePath( raw )
	if type( raw ) ~= "string" then return nil end
	local path = string.lower( Trim( raw ) )
	path = string.gsub( path, "\\", "/" )
	path = string.gsub( path, "/+", "/" )

	if path == "" or #path > S.LIMITS.PATH_BYTES then return nil end
	if string.find( path, "[%z\1-\31]" ) then return nil end
	if string.sub( path, 1, 1 ) == "/" or string.find( path, "^%a:" ) then return nil end
	if string.find( path, "://", 1, true ) or string.find( path, ":", 1, true ) then return nil end

	for part in string.gmatch( path, "[^/]+" ) do
		if part == "." or part == ".." then return nil end
		-- ToPBR's output is owned by the RTX client, not this addon.  Reject it at
		-- the shared/server boundary as well as in the native importer so a profile
		-- can never use the writer as a reader for ~gmod_topbr.
		if part == "~gmod_topbr" then return nil end
	end

	return path
end

--- Whether `path` names a DDS texture inside an RTX Remix mod folder other
--- than AME's own: an enhancement map. The client decodes one of these into
--- an image before a bake operation can reach the native writer
--- (cl_28_rtx_enhance.lua), so it is the one kind of DDS a map operation may
--- name. AME's own folder is retired by its writer on every server join.
function S.IsModTexture( path )
	if type( path ) ~= "string" then return false end
	local folder = string.match( string.lower( path ), "^rtx%-remix/mods/([^/]+)/.+%.dds$" )
	return folder ~= nil and folder ~= "!advanced_material_editor" and folder ~= "~gmod_topbr"
end

local function NormalizeMaterial( raw )
	local path = SafeRelativePath( raw )
	if not path then return nil end
	path = string.gsub( path, "^materials/", "" )
	path = string.gsub( path, "%.vmt$", "" )
	path = string.gsub( path, "%.vtf$", "" )
	if path == "" then return nil end
	return path
end

local function NormalizeModel( raw )
	local path = SafeRelativePath( raw )
	if not path or string.sub( path, -4 ) ~= ".mdl" then return nil end
	return path
end

local function NormalizeHash( raw )
	if type( raw ) ~= "string" then return nil end
	local hash = string.upper( Trim( raw ) )
	hash = string.gsub( hash, "^0X", "" )
	if #hash < 1 or #hash > 16 or string.find( hash, "[^0-9A-F]" ) then return nil end
	hash = string.rep( "0", 16 - #hash ) .. hash
	if hash == "0000000000000000" then return nil end
	return "0x" .. hash
end

local function ValidID( raw )
	if type( raw ) ~= "string" then return nil end
	local id = Trim( raw )
	if id == "" or #id > S.LIMITS.ID_BYTES then return nil end
	if string.find( id, "[^%w_%.%-]" ) then return nil end
	return id
end

local function CopyKnownMap( raw )
	if type( raw ) == "string" then return raw end
	local out = { source = raw.source, generated = true, ops = {} }
	if raw.recipe then
		-- The source has already crossed SafeRecipeCopy.  Calling it again keeps
		-- this helper independent from table.Copy and preserves the same bound.
		out.recipe = SafeRecipeCopy( raw.recipe, "map.recipe", {} )
	end
	for index, op in ipairs( raw.ops or {} ) do
		local copy = { op = op.op }
		if op.value ~= nil then copy.value = op.value end
		if op.color then copy.color = CopyColor( op.color ) end
		if op.strength ~= nil then copy.strength = op.strength end
		if op.channel ~= nil then copy.channel = op.channel end
		out.ops[ index ] = copy
	end
	return out
end

---------------------------------------------------------------------------
-- Map descriptors
---------------------------------------------------------------------------

local function SanitizeMapOp( raw, path, errors )
	if not IsTable( raw ) or type( raw.op ) ~= "string" then
		AddError( errors, path, "must name a map operation" )
		return nil
	end

	local kind = string.lower( Trim( raw.op ) )
	if kind == "invert" then
		return { op = "invert" }
	elseif kind == "multiply" then
		local hasValue = raw.value ~= nil
		local hasColor = raw.color ~= nil
		if hasValue == hasColor then
			AddError( errors, path, "multiply needs exactly one of value or color" )
			return nil
		end
		if hasValue then
			-- The native image baker represents a scalar factor as a colour and
			-- accepts only non-negative channels in the [0, 16] range.
			local value = ReadNumber( raw.value, 1, 0, 16, path .. ".value", errors )
			return { op = "multiply", value = value }
		end
		local color = ReadColor( raw.color, { r = 1, g = 1, b = 1 }, 0, 16,
			path .. ".color", errors )
		return { op = "multiply", color = color }
	elseif kind == "normal_from_height" then
		local strength = ReadNumber( raw.strength, 1, 0.01, 32,
			path .. ".strength", errors )
		local channel = ReadEnum( raw.channel, "luminance", CHANNELS,
			path .. ".channel", errors )
		return { op = "normal_from_height", strength = strength, channel = channel }
	end

	AddError( errors, path, "uses an unsupported map operation" )
	return nil
end

local function SanitizeMap( raw, path, errors )
	if type( raw ) == "string" then
		local source = SafeRelativePath( raw )
		if not source then AddError( errors, path, "contains an unsafe texture path" ) end
		return source
	end

	if not IsTable( raw ) then
		AddError( errors, path, "must be a texture path or bake descriptor" )
		return nil
	end

	local source = SafeRelativePath( raw.source )
	if not source then
		AddError( errors, path .. ".source", "contains an unsafe texture path" )
		return nil
	end

	local count = DenseLength( raw.ops or {}, S.LIMITS.MAP_OPS, path .. ".ops", errors )
	if count == nil then return nil end
	local recipe = SanitizeRecipe( raw.recipe, path .. ".recipe", errors )
	if raw.recipe ~= nil and not recipe then return nil end
	if count > 0 and not recipe and string.sub( string.lower( source ), -4 ) == ".dds"
		and not S.IsModTexture( source ) then
		AddError( errors, path .. ".ops",
			"cannot bake operations directly into DDS; edit or pre-bake a PNG/image source" )
		return nil
	end
	if count == 0 and not recipe then return source end

	local out = { source = source, generated = true, ops = {} }
	if recipe then out.recipe = recipe end
	for index = 1, count do
		local op = SanitizeMapOp( raw.ops[ index ], path .. ".ops[" .. index .. "]", errors )
		if op then out.ops[ #out.ops + 1 ] = op end
	end
	if #out.ops ~= count then return nil end
	return out
end

S.SanitizeMap = function( raw )
	local errors = {}
	local clean = SanitizeMap( raw, "map", errors )
	if #errors > 0 then return nil, errors end
	return clean, errors
end

---------------------------------------------------------------------------
-- Target and PBR state
---------------------------------------------------------------------------

local function SanitizeTarget( raw, errors )
	if not IsTable( raw ) then
		AddError( errors, "target", "must be a table" )
		return nil
	end

	local kind = type( raw.kind ) == "string" and string.lower( Trim( raw.kind ) ) or ""
	if not TARGET_KINDS[ kind ] then
		AddError( errors, "target.kind", "must be material, model, or hash" )
		return nil
	end

	local out = { kind = kind }
	if raw.material ~= nil then
		out.material = NormalizeMaterial( raw.material )
		if not out.material then AddError( errors, "target.material", "is not a safe material path" ) end
	end
	if raw.model ~= nil then
		out.model = NormalizeModel( raw.model )
		if not out.model then AddError( errors, "target.model", "is not a safe .mdl path" ) end
	end

	if out.model then
		local slot = FiniteNumber( raw.slot or 0 )
		if not slot then
			AddError( errors, "target.slot", "must be a finite integer" )
		else
			out.slot = math.floor( Clamp( slot, 0, 127 ) )
		end
	elseif raw.slot ~= nil then
		AddError( errors, "target.slot", "requires target.model" )
	end

	local hashes, seen = {}, {}
	local function AddHash( rawHash, path )
		local hash = NormalizeHash( rawHash )
		if not hash then
			AddError( errors, path, "must be a non-zero 1-16 digit hexadecimal hash" )
			return
		end
		if not seen[ hash ] then
			seen[ hash ] = true
			hashes[ #hashes + 1 ] = hash
		end
	end

	if raw.hash ~= nil then AddHash( raw.hash, "target.hash" ) end
	if raw.hashes ~= nil then
		local count = DenseLength( raw.hashes, S.LIMITS.HASHES, "target.hashes", errors )
		if count then
			for index = 1, count do AddHash( raw.hashes[ index ], "target.hashes[" .. index .. "]" ) end
		end
	end
	if #hashes > S.LIMITS.HASHES then
		AddError( errors, "target.hashes", "exceeds the limit of " .. S.LIMITS.HASHES )
	end
	table.sort( hashes )
	if #hashes > 0 then
		out.hash   = hashes[ 1 ]
		out.hashes = hashes
	end

	if kind == "material" and not out.material then
		AddError( errors, "target.material", "is required for a material target" )
	elseif kind == "model" and not out.model then
		AddError( errors, "target.model", "is required for a model target" )
	elseif kind == "hash" and #hashes == 0 then
		AddError( errors, "target.hashes", "needs at least one valid hash" )
	end

	return out
end

function S.SanitizeTarget( raw )
	local errors = {}
	local clean = SanitizeTarget( raw, errors )
	if #errors > 0 then return nil, errors end
	return clean, errors
end

local function SanitizePBR( raw, errors )
	if raw ~= nil and not IsTable( raw ) then
		AddError( errors, "pbr", "must be a table" )
		raw = {}
	end
	raw = raw or {}

	local rawConstants = raw.constants
	if rawConstants ~= nil and not IsTable( rawConstants ) then
		AddError( errors, "pbr.constants", "must be a table" )
		rawConstants = {}
	end
	rawConstants = rawConstants or {}

	local defaults = S.DEFAULT_CONSTANTS
	local constants = {
		albedo = ReadColor( rawConstants.albedo, defaults.albedo, 0, 1,
			"pbr.constants.albedo", errors ),
		opacity = ReadNumber( rawConstants.opacity, defaults.opacity, 0, 1,
			"pbr.constants.opacity", errors ),
		roughness = ReadNumber( rawConstants.roughness, defaults.roughness, 0, 1,
			"pbr.constants.roughness", errors ),
		metallic = ReadNumber( rawConstants.metallic, defaults.metallic, 0, 1,
			"pbr.constants.metallic", errors ),
		emissive_color = ReadColor( rawConstants.emissive_color, defaults.emissive_color, 0, 1,
			"pbr.constants.emissive_color", errors ),
		emissive_intensity = ReadNumber( rawConstants.emissive_intensity,
			defaults.emissive_intensity, 0, 65504, "pbr.constants.emissive_intensity", errors ),
		anisotropy = ReadNumber( rawConstants.anisotropy, defaults.anisotropy, -1, 1,
			"pbr.constants.anisotropy", errors ),
		thin_film_thickness = ReadNumber( rawConstants.thin_film_thickness,
			defaults.thin_film_thickness, 0, 1500, "pbr.constants.thin_film_thickness", errors ),
		displace_in = ReadNumber( rawConstants.displace_in, defaults.displace_in, 0, 0.2,
			"pbr.constants.displace_in", errors ),
		displace_out = ReadNumber( rawConstants.displace_out, defaults.displace_out, 0, 0.2,
			"pbr.constants.displace_out", errors ),
		subsurface_transmittance_color = ReadColor( rawConstants.subsurface_transmittance_color,
			defaults.subsurface_transmittance_color, 0, 1,
			"pbr.constants.subsurface_transmittance_color", errors ),
		subsurface_measurement_distance = ReadNumber( rawConstants.subsurface_measurement_distance,
			defaults.subsurface_measurement_distance, 0, 16,
			"pbr.constants.subsurface_measurement_distance", errors ),
		subsurface_single_scattering_albedo = ReadColor(
			rawConstants.subsurface_single_scattering_albedo,
			defaults.subsurface_single_scattering_albedo, 0, 1,
			"pbr.constants.subsurface_single_scattering_albedo", errors ),
		subsurface_volumetric_anisotropy = ReadNumber(
			rawConstants.subsurface_volumetric_anisotropy,
			defaults.subsurface_volumetric_anisotropy, -0.99, 0.99,
			"pbr.constants.subsurface_volumetric_anisotropy", errors ),
		subsurface_radius = ReadColor( rawConstants.subsurface_radius,
			defaults.subsurface_radius, 0, 1, "pbr.constants.subsurface_radius", errors ),
		subsurface_radius_scale = ReadNumber( rawConstants.subsurface_radius_scale,
			defaults.subsurface_radius_scale, 0, 1000,
			"pbr.constants.subsurface_radius_scale", errors ),
		subsurface_max_sample_radius = ReadNumber( rawConstants.subsurface_max_sample_radius,
			defaults.subsurface_max_sample_radius, 0, 65504,
			"pbr.constants.subsurface_max_sample_radius", errors ),
	}

	local maps = {}
	local rawMaps = raw.maps
	if rawMaps ~= nil and not IsTable( rawMaps ) then
		AddError( errors, "pbr.maps", "must be a table" )
		rawMaps = {}
	end
	for key in pairs( MAP_KEYS ) do
		if rawMaps and rawMaps[ key ] ~= nil then
			local clean = SanitizeMap( rawMaps[ key ], "pbr.maps." .. key, errors )
			if clean then maps[ key ] = clean end
		end
	end

	local rawOptions = raw.options
	if rawOptions ~= nil and not IsTable( rawOptions ) then
		AddError( errors, "pbr.options", "must be a table" )
		rawOptions = {}
	end
	rawOptions = rawOptions or {}
	local optionDefaults = S.DEFAULT_OPTIONS
	-- Profiles written before the 1.5.2 control expansion did not persist the
	-- three feature-enable flags.  Preserve their visual result when loading,
	-- while allowing every newly saved explicit false value to remain false.
	local rawThinFilm = FiniteNumber( rawConstants.thin_film_thickness )
	local rawEmission = FiniteNumber( rawConstants.emissive_intensity )
	local inferredThinFilm = ( rawThinFilm ~= nil and rawThinFilm > 0 )
		or rawOptions.alpha_is_thin_film == true or rawOptions.alpha_is_thin_film == 1
	local inferredEmission = maps.emissive ~= nil
		or ( rawEmission ~= nil and rawEmission > 0 )
	local inferredBlend = rawOptions.blend_type ~= nil
		and string.lower( Trim( tostring( rawOptions.blend_type ) ) ) ~= "opaque"
	local options = {
		filter_mode = ReadEnum( rawOptions.filter_mode, optionDefaults.filter_mode,
			FILTER_MODES, "pbr.options.filter_mode", errors ),
		wrap_u = ReadEnum( rawOptions.wrap_u, optionDefaults.wrap_u,
			WRAP_MODES, "pbr.options.wrap_u", errors ),
		wrap_v = ReadEnum( rawOptions.wrap_v, optionDefaults.wrap_v,
			WRAP_MODES, "pbr.options.wrap_v", errors ),
		alpha_is_thin_film = ReadBoolean( rawOptions.alpha_is_thin_film,
			optionDefaults.alpha_is_thin_film, "pbr.options.alpha_is_thin_film", errors ),
		use_draw_call_alpha = ReadBoolean( rawOptions.use_draw_call_alpha,
			optionDefaults.use_draw_call_alpha, "pbr.options.use_draw_call_alpha", errors ),
		inverted_blend = ReadBoolean( rawOptions.inverted_blend,
			optionDefaults.inverted_blend, "pbr.options.inverted_blend", errors ),
		blend_type = ReadEnum( rawOptions.blend_type, optionDefaults.blend_type,
			BLEND_TYPES, "pbr.options.blend_type", errors ),
		alpha_test_type = ReadEnum( rawOptions.alpha_test_type, optionDefaults.alpha_test_type,
			ALPHA_TESTS, "pbr.options.alpha_test_type", errors ),
		alpha_reference = ReadNumber( rawOptions.alpha_reference, optionDefaults.alpha_reference,
			0, 1, "pbr.options.alpha_reference", errors ),
		sprite_sheet_rows = ReadInteger( rawOptions.sprite_sheet_rows,
			optionDefaults.sprite_sheet_rows, 1, 255, "pbr.options.sprite_sheet_rows", errors ),
		sprite_sheet_columns = ReadInteger( rawOptions.sprite_sheet_columns,
			optionDefaults.sprite_sheet_columns, 1, 255, "pbr.options.sprite_sheet_columns", errors ),
		sprite_sheet_fps = ReadInteger( rawOptions.sprite_sheet_fps,
			optionDefaults.sprite_sheet_fps, 0, 255, "pbr.options.sprite_sheet_fps", errors ),
		enable_thin_film = ReadBoolean( rawOptions.enable_thin_film,
			rawOptions.enable_thin_film == nil and inferredThinFilm or optionDefaults.enable_thin_film,
			"pbr.options.enable_thin_film", errors ),
		enable_emission = ReadBoolean( rawOptions.enable_emission,
			rawOptions.enable_emission == nil and inferredEmission or optionDefaults.enable_emission,
			"pbr.options.enable_emission", errors ),
		preload_textures = ReadBoolean( rawOptions.preload_textures,
			optionDefaults.preload_textures, "pbr.options.preload_textures", errors ),
		ignore_material = ReadBoolean( rawOptions.ignore_material,
			optionDefaults.ignore_material, "pbr.options.ignore_material", errors ),
		blend_enabled = ReadBoolean( rawOptions.blend_enabled,
			rawOptions.blend_enabled == nil and inferredBlend or optionDefaults.blend_enabled,
			"pbr.options.blend_enabled", errors ),
		normal_encoding = ReadEnum( rawOptions.normal_encoding, optionDefaults.normal_encoding,
			NORMAL_ENCODINGS, "pbr.options.normal_encoding", errors ),
		subsurface_diffusion_profile = ReadBoolean( rawOptions.subsurface_diffusion_profile,
			optionDefaults.subsurface_diffusion_profile,
			"pbr.options.subsurface_diffusion_profile", errors ),
	}
	-- `opaque` predates the explicit blend-enabled switch and means "do not
	-- author a blend type"; it is not an AperturePBR BlendType enum member.
	-- Once blending is enabled the omitted MDL field would silently default to
	-- Alpha, so make that effective value explicit and truthful in the UI.
	if options.blend_enabled and options.blend_type == "opaque" then
		options.blend_type = "alpha"
	end

	return { constants = constants, maps = maps, options = options }
end

---------------------------------------------------------------------------
-- Graph sanitising and validation
---------------------------------------------------------------------------

function S.DefaultGraph()
	return {
		nodes = { { id = "output", type = "output_surface", x = 640, y = 240, params = {} } },
		links = {},
		-- A marked socket has been explicitly edited in the graph.  Its lack of
		-- a link therefore means "use the material default", not "resurrect the
		-- imported pbr side-table value".  Per-socket ownership lets old/imported
		-- profiles keep their fallback values until that particular input is
		-- actually touched in the node editor.
		authoritative = {},
	}
end

local function SanitizeNodeParams( nodeType, raw, path, errors )
	if raw ~= nil and not IsTable( raw ) then
		AddError( errors, path, "must be a table" )
		raw = {}
	end
	raw = raw or {}

	if nodeType == "texture" then
		local texture = SafeRelativePath( raw.texture or raw.path )
		if not texture then AddError( errors, path .. ".texture", "contains an unsafe texture path" ) end
		local recipe = SanitizeRecipe( raw.recipe, path .. ".recipe", errors )
		if raw.recipe ~= nil and not recipe then return {} end
		local out = texture and { texture = texture } or {}
		if recipe then out.recipe = recipe end
		return out
	elseif nodeType == "value" then
		return { value = ReadNumber( raw.value, 0, -1000000, 1000000, path .. ".value", errors ) }
	elseif nodeType == "color" then
		-- Values above one are useful as a multiply/tint operand.  A colour
		-- connected straight to a material output is clamped to the API range
		-- by Compile; keeping the wider intermediate range makes graph math sane.
		return { color = ReadColor( raw.color, { r = 1, g = 1, b = 1 }, 0, 16,
			path .. ".color", errors ) }
	elseif nodeType == "invert" then
		return { value = ReadNumber( raw.value, 0, -1000000, 1000000, path .. ".value", errors ) }
	elseif nodeType == "multiply" then
		return {
			-- Unlinked multiply operands can become native texture-bake factors,
			-- so expose the native writer's useful, representable range here.
			a = ReadNumber( raw.a, 1, 0, 16, path .. ".a", errors ),
			b = ReadNumber( raw.b, 1, 0, 16, path .. ".b", errors ),
		}
	elseif nodeType == "normal_from_height" then
		return {
			strength = ReadNumber( raw.strength, 1, 0.01, 32, path .. ".strength", errors ),
			channel = ReadEnum( raw.channel, "luminance", CHANNELS, path .. ".channel", errors ),
		}
	end

	return {}
end

local function SanitizeNode( raw, index, errors )
	local path = "graph.nodes[" .. index .. "]"
	if not IsTable( raw ) then
		AddError( errors, path, "must be a table" )
		return nil
	end

	local id = ValidID( raw.id )
	if not id then AddError( errors, path .. ".id", "is invalid" ) end

	local nodeType = type( raw.type ) == "string" and string.lower( Trim( raw.type ) ) or ""
	nodeType = NODE_TYPE_ALIASES[ nodeType ] or nodeType
	if not S.NODE_TYPES[ nodeType ] then AddError( errors, path .. ".type", "is not allowlisted" ) end
	if not id or not S.NODE_TYPES[ nodeType ] then return nil end

	local out = {
		id     = id,
		type   = nodeType,
		x      = ReadNumber( raw.x, 0, -100000, 100000, path .. ".x", errors ),
		y      = ReadNumber( raw.y, 0, -100000, 100000, path .. ".y", errors ),
		params = SanitizeNodeParams( nodeType, raw.params, path .. ".params", errors ),
	}

	if raw.label ~= nil then
		if type( raw.label ) ~= "string" then
			AddError( errors, path .. ".label", "must be a string" )
		else
			local label = Trim( raw.label )
			if #label > S.LIMITS.LABEL_BYTES then
				AddError( errors, path .. ".label", "is too long" )
			elseif label ~= "" then
				out.label = label
			end
		end
	end

	return out
end

local function Endpoint( raw, side, path, errors )
	local nested = IsTable( raw[ side ] ) and raw[ side ] or nil
	local node = nested and nested.node or raw[ side .. "_node" ]
	local socket = nested and nested.socket or raw[ side .. "_socket" ]
	node = ValidID( node )
	if not node then AddError( errors, path .. "." .. side .. ".node", "is invalid" ) end
	if type( socket ) ~= "string" then
		AddError( errors, path .. "." .. side .. ".socket", "is invalid" )
		return node, nil
	end
	socket = string.lower( Trim( socket ) )
	if socket == "" or #socket > S.LIMITS.ID_BYTES or string.find( socket, "[^%w_]" ) then
		AddError( errors, path .. "." .. side .. ".socket", "is invalid" )
		return node, nil
	end
	return node, socket
end

local function SanitizeLink( raw, index, errors )
	local path = "graph.links[" .. index .. "]"
	if not IsTable( raw ) then
		AddError( errors, path, "must be a table" )
		return nil
	end
	local fromNode, fromSocket = Endpoint( raw, "from", path, errors )
	local toNode, toSocket     = Endpoint( raw, "to", path, errors )
	if not fromNode or not fromSocket or not toNode or not toSocket then return nil end
	return {
		from = { node = fromNode, socket = fromSocket },
		to   = { node = toNode, socket = toSocket },
	}
end

local function SocketAccepts( wanted, actual )
	if wanted == "numeric" then return actual == "number" or actual == "color" end
	return wanted == actual
end

local function ValidateCleanGraph( graph, errors )
	local nodes, outputCount = {}, 0
	for index, node in ipairs( graph.nodes ) do
		if nodes[ node.id ] then
			AddError( errors, "graph.nodes[" .. index .. "].id", "duplicates node " .. node.id )
		else
			nodes[ node.id ] = node
		end
		if node.type == "output_surface" then outputCount = outputCount + 1 end
	end
	if outputCount ~= 1 then AddError( errors, "graph.nodes", "must contain exactly one output_surface" ) end

	local incoming, outgoing, destinations, linksSeen = {}, {}, {}, {}
	for index, link in ipairs( graph.links ) do
		local path = "graph.links[" .. index .. "]"
		local source = nodes[ link.from.node ]
		local target = nodes[ link.to.node ]
		if not source then AddError( errors, path .. ".from.node", "does not exist" ) end
		if not target then AddError( errors, path .. ".to.node", "does not exist" ) end

		local sourceType = source and S.NODE_TYPES[ source.type ].outputs[ link.from.socket ] or nil
		local wantedType = target and S.NODE_TYPES[ target.type ].inputs[ link.to.socket ] or nil
		if source and not sourceType then AddError( errors, path .. ".from.socket", "does not exist" ) end
		if target and not wantedType then AddError( errors, path .. ".to.socket", "does not exist" ) end

		local destination = link.to.node .. "\1" .. link.to.socket
		local identity = link.from.node .. "\1" .. link.from.socket .. "\1" .. destination
		if linksSeen[ identity ] then AddError( errors, path, "duplicates another link" ) end
		linksSeen[ identity ] = true
		if destinations[ destination ] then AddError( errors, path .. ".to", "already has an incoming link" ) end
		destinations[ destination ] = true

		if source and target and sourceType and wantedType then
			incoming[ link.to.node ] = incoming[ link.to.node ] or {}
			incoming[ link.to.node ][ link.to.socket ] = link
			outgoing[ link.from.node ] = outgoing[ link.from.node ] or {}
			outgoing[ link.from.node ][ #outgoing[ link.from.node ] + 1 ] = link.to.node
		end
	end

	-- Reject every cycle, including one in a disconnected editor fragment.
	local visiting, visited = {}, {}
	local function Visit( id )
		if visiting[ id ] then return false end
		if visited[ id ] then return true end
		visiting[ id ] = true
		for _, nextID in ipairs( outgoing[ id ] or {} ) do
			if not Visit( nextID ) then return false end
		end
		visiting[ id ] = nil
		visited[ id ] = true
		return true
	end
	for id in pairs( nodes ) do
		if not Visit( id ) then
			AddError( errors, "graph.links", "contains a cycle" )
			break
		end
	end

	-- Infer the two polymorphic node types, then verify every connection with
	-- its real type rather than accepting a misleading dynamic placeholder.
	local inferred, inferring = {}, {}
	local function Infer( nodeID, socket )
		local cacheKey = nodeID .. "\1" .. socket
		if inferred[ cacheKey ] then return inferred[ cacheKey ] end
		if inferring[ cacheKey ] then return nil end
		inferring[ cacheKey ] = true

		local node = nodes[ nodeID ]
		if not node then return nil end
		local declared = S.NODE_TYPES[ node.type ].outputs[ socket ]
		local actual = declared

		local function InputType( input, fallback )
			local link = incoming[ nodeID ] and incoming[ nodeID ][ input ]
			if not link then return fallback end
			return Infer( link.from.node, link.from.socket )
		end

		if node.type == "invert" and socket == "value" then
			actual = InputType( "value", "number" )
		elseif node.type == "multiply" and socket == "value" then
			local a = InputType( "a", "number" )
			local b = InputType( "b", "number" )
			if ( a == "number" or a == "color" ) and ( b == "number" or b == "color" ) then
				actual = ( a == "color" or b == "color" ) and "color" or "number"
			else
				actual = nil
			end
		end

		inferring[ cacheKey ] = nil
		inferred[ cacheKey ] = actual
		return actual
	end

	for index, link in ipairs( graph.links ) do
		local source = nodes[ link.from.node ]
		local target = nodes[ link.to.node ]
		if source and target then
			local wanted = S.NODE_TYPES[ target.type ].inputs[ link.to.socket ]
			local actual = Infer( source.id, link.from.socket )
			if wanted and actual and not SocketAccepts( wanted, actual ) then
				AddError( errors, "graph.links[" .. index .. "]", "cannot connect " .. actual .. " to " .. wanted )
			elseif wanted and not actual then
				AddError( errors, "graph.links[" .. index .. "]", "has an unresolved source type" )
			end
		end
	end

	return nodes, incoming
end

local function SanitizeGraph( raw, errors )
	if raw == nil then return S.DefaultGraph() end
	if not IsTable( raw ) then
		AddError( errors, "graph", "must be a table" )
		return nil
	end

	local nodeCount = DenseLength( raw.nodes or {}, S.LIMITS.NODES, "graph.nodes", errors )
	local linkCount = DenseLength( raw.links or {}, S.LIMITS.LINKS, "graph.links", errors )
	if nodeCount == nil or linkCount == nil then return nil end

	local authoritative = {}
	if raw.authoritative ~= nil then
		if not IsTable( raw.authoritative ) then
			AddError( errors, "graph.authoritative", "must be a table" )
		else
			for socket, enabled in pairs( raw.authoritative ) do
				if type( socket ) ~= "string" or not S.NODE_TYPES.output_surface.inputs[ socket ] then
					AddError( errors, "graph.authoritative." .. tostring( socket ),
						"is not an output-surface socket" )
				elseif type( enabled ) ~= "boolean" then
					AddError( errors, "graph.authoritative." .. socket, "must be a boolean" )
				elseif enabled then
					authoritative[ socket ] = true
				end
			end
		end
	end

	local graph = { nodes = {}, links = {}, authoritative = authoritative }
	for index = 1, nodeCount do
		local node = SanitizeNode( raw.nodes[ index ], index, errors )
		if node then graph.nodes[ #graph.nodes + 1 ] = node end
	end
	for index = 1, linkCount do
		local link = SanitizeLink( raw.links[ index ], index, errors )
		if link then graph.links[ #graph.links + 1 ] = link end
	end

	if #graph.nodes ~= nodeCount or #graph.links ~= linkCount then return nil end
	ValidateCleanGraph( graph, errors )
	return graph
end

function S.SanitizeGraph( raw )
	local errors = {}
	local clean = SanitizeGraph( raw, errors )
	if #errors > 0 then return nil, errors end
	return clean, errors
end

---------------------------------------------------------------------------
-- Migration and whole-profile sanitising
---------------------------------------------------------------------------

-- Version zero was the unversioned prototype shape.  This migration is
-- intentionally narrow: it moves only fields that are part of version one,
-- so arbitrary data from a preset cannot hitch a ride into the saved profile.
function S.Migrate( raw )
	local errors = {}
	if not IsTable( raw ) then
		AddError( errors, "profile", "must be a table" )
		return nil, errors
	end

	local version = raw.version
	if version == nil then version = 0 end
	version = FiniteNumber( version )
	if not version or version ~= math.floor( version ) then
		AddError( errors, "version", "must be an integer" )
		return nil, errors
	end
	if version < 0 or version > S.VERSION then
		AddError( errors, "version", "is not supported by this build" )
		return nil, errors
	end

	if version == 0 then
		local target = raw.target
		if not IsTable( target ) then
			local kind = raw.kind
			if kind == nil then
				if raw.model ~= nil then kind = "model"
				elseif raw.hash ~= nil or raw.hashes ~= nil then kind = "hash"
				elseif raw.material ~= nil then kind = "material" end
			end
			target = {
				kind     = kind,
				material = raw.material,
				hash     = raw.hash,
				hashes   = raw.hashes,
				model    = raw.model,
				slot     = raw.slot,
			}
		end

		local pbr = raw.pbr
		if not IsTable( pbr ) then
			pbr = {
				constants = raw.constants,
				maps      = raw.maps,
				options   = raw.options,
			}
		end

		return {
			version = S.VERSION,
			target  = target,
			pbr     = pbr,
			graph   = raw.graph,
		}, errors
	end

	-- Sanitizers below copy every retained field, so referencing these source
	-- tables here cannot mutate the caller's version-one profile.
	return {
		version = S.VERSION,
		target  = raw.target,
		pbr     = raw.pbr,
		graph   = raw.graph,
	}, errors
end

function S.Sanitize( raw )
	local migrated, errors = S.Migrate( raw )
	if not migrated then return nil, errors end

	local target = SanitizeTarget( migrated.target, errors )
	local pbr = SanitizePBR( migrated.pbr, errors )
	local graph = SanitizeGraph( migrated.graph, errors )

	if #errors > 0 or not target or not graph then return nil, errors end
	return { version = S.VERSION, target = target, pbr = pbr, graph = graph }, errors
end

S.SanitizeProfile = S.Sanitize

function S.Validate( raw )
	local clean, errors = S.Sanitize( raw )
	return clean ~= nil, errors
end

---------------------------------------------------------------------------
-- Deterministic identity
---------------------------------------------------------------------------

local function NumberText( number )
	if number == 0 then return "0" end -- folds negative zero as well
	return string.lower( string.format( "%.17g", number ) )
end

local function EncodeCanonical( value, seen, depth )
	local kind = type( value )
	if kind == "nil" then return "n" end
	if kind == "boolean" then return value and "b1" or "b0" end
	if kind == "number" then
		if not FiniteNumber( value ) then return nil, "non-finite number" end
		return "d" .. NumberText( value )
	end
	if kind == "string" then return "s" .. #value .. ":" .. value end
	if kind ~= "table" then return nil, "unsupported " .. kind end
	if depth >= S.LIMITS.DEPTH then return nil, "table nesting is too deep" end
	if seen[ value ] then return nil, "cyclic table" end
	seen[ value ] = true

	local count, greatest, numericOnly = 0, 0, true
	for key in pairs( value ) do
		count = count + 1
		if type( key ) ~= "number" or key < 1 or key ~= math.floor( key ) then
			numericOnly = false
		elseif key > greatest then
			greatest = key
		end
	end

	local parts = {}
	if numericOnly and count == greatest then
		for index = 1, count do
			local encoded, reason = EncodeCanonical( value[ index ], seen, depth + 1 )
			if not encoded then seen[ value ] = nil return nil, reason end
			parts[ #parts + 1 ] = encoded
		end
		seen[ value ] = nil
		return "a" .. count .. "[" .. table.concat( parts, "" ) .. "]"
	end

	local keys = {}
	for key in pairs( value ) do keys[ #keys + 1 ] = key end
	table.sort( keys, function( a, b )
		local ta, tb = type( a ), type( b )
		if ta ~= tb then return ta < tb end
		return tostring( a ) < tostring( b )
	end )
	for _, key in ipairs( keys ) do
		local encodedKey, keyReason = EncodeCanonical( key, seen, depth + 1 )
		local encodedValue, valueReason = EncodeCanonical( value[ key ], seen, depth + 1 )
		if not encodedKey or not encodedValue then
			seen[ value ] = nil
			return nil, keyReason or valueReason
		end
		parts[ #parts + 1 ] = encodedKey .. encodedValue
	end
	seen[ value ] = nil
	return "m" .. #keys .. "{" .. table.concat( parts, "" ) .. "}"
end

function S.Canonical( value )
	return EncodeCanonical( value, {}, 0 )
end

local function CanonicalProfileTable( clean )
	local nodes = CopyArray( clean.graph.nodes )
	table.sort( nodes, function( a, b ) return a.id < b.id end )

	local links = CopyArray( clean.graph.links )
	table.sort( links, function( a, b )
		local aa = a.to.node .. "\1" .. a.to.socket .. "\1" .. a.from.node .. "\1" .. a.from.socket
		local bb = b.to.node .. "\1" .. b.to.socket .. "\1" .. b.from.node .. "\1" .. b.from.socket
		return aa < bb
	end )

	return {
		version = clean.version,
		target  = clean.target,
		pbr     = clean.pbr,
		-- Authority changes the effective output when a socket has no link, so
		-- it is material content and must participate in profile identity.
		graph   = { nodes = nodes, links = links, authoritative = clean.graph.authoritative },
	}
end

function S.CanonicalProfile( raw )
	local clean, errors = S.Sanitize( raw )
	if not clean then return nil, errors end
	local canonical, reason = S.Canonical( CanonicalProfileTable( clean ) )
	if not canonical then return nil, { "profile: " .. tostring( reason ) } end
	return canonical, errors
end

-- Two independent 32-bit DJB passes avoid a Garry's Mod util dependency while
-- still producing compact, deterministic identifiers on client, server, and
-- in the standalone Lupa harness.
function S.Hash( text )
	text = tostring( text or "" )
	local a, b = 5381, 52711
	for index = 1, #text do
		local byte = string.byte( text, index )
		a = ( a * 33 + byte ) % 4294967296
		b = ( b * 65599 + byte + index ) % 4294967296
	end
	return string.format( "%08x%08x", a, b )
end

function S.RuleID( raw )
	local target = raw
	if IsTable( raw ) and raw.target then target = raw.target end
	local clean, errors = S.SanitizeTarget( target )
	if not clean then return nil, errors end

	if clean.kind == "material" then
		return "rtx:mat:" .. clean.material, errors
	elseif clean.kind == "model" then
		return "rtx:mdl:" .. clean.model .. ":" .. tostring( clean.slot or 0 ), errors
	end

	local canonical = S.Canonical( clean.hashes )
	return "rtx:hsh:" .. S.Hash( canonical ), errors
end

function S.ProfileID( raw )
	local canonical, errors = S.CanonicalProfile( raw )
	if not canonical then return nil, errors end
	return "rtxp" .. S.VERSION .. ":" .. S.Hash( canonical ), errors
end

---------------------------------------------------------------------------
-- Node graph compiler
---------------------------------------------------------------------------

local function CopyPBR( source )
	local constants = {}
	for key, value in pairs( source.constants ) do
		constants[ key ] = IsTable( value ) and CopyColor( value ) or value
	end
	local maps = {}
	for key, value in pairs( source.maps ) do maps[ key ] = CopyKnownMap( value ) end
	local options = {}
	for key, value in pairs( source.options ) do options[ key ] = value end
	return { constants = constants, maps = maps, options = options }
end

local function Constant( valueType, value )
	return { value_type = valueType, constant = value }
end

local function TextureValue( valueType, map )
	return { value_type = valueType, map = map }
end

local function AppendMapOp( map, op, errors, path )
	local source = type( map ) == "string" and map or ( map and map.source )
	local hasRecipe = type( map ) == "table" and map.recipe ~= nil
	if type( source ) == "string" and not hasRecipe
		and string.sub( string.lower( source ), -4 ) == ".dds" and not S.IsModTexture( source ) then
		AddError( errors, path,
			"cannot bake operations directly into DDS; edit or pre-bake a PNG/image source" )
		return nil
	end
	local descriptor
	if type( map ) == "string" then
		descriptor = { source = map, generated = true, ops = {} }
	else
		descriptor = CopyKnownMap( map )
	end
	if #descriptor.ops >= S.LIMITS.MAP_OPS then
		AddError( errors, path, "would exceed the map-operation limit" )
		return nil
	end
	-- Graph arithmetic can feed a general value node into a texture multiply.
	-- Re-run the same operation sanitizer used by saved descriptors so such a
	-- path cannot bypass the native baker's non-negative, bounded factors.
	local cleanOp = SanitizeMapOp( op, path .. ".operation", errors )
	if not cleanOp then return nil end
	descriptor.ops[ #descriptor.ops + 1 ] = cleanOp
	return descriptor
end

local function MultiplyColor( left, right )
	if type( left ) == "number" then
		return { r = left * right.r, g = left * right.g, b = left * right.b }
	elseif type( right ) == "number" then
		return { r = left.r * right, g = left.g * right, b = left.b * right }
	end
	return { r = left.r * right.r, g = left.g * right.g, b = left.b * right.b }
end

function S.Compile( raw )
	local clean, errors = S.Sanitize( raw )
	if not clean then return nil, errors end

	local nodes, incoming = ValidateCleanGraph( clean.graph, errors )
	if #errors > 0 then return nil, errors end

	local output
	for _, node in ipairs( clean.graph.nodes ) do
		if node.type == "output_surface" then output = node break end
	end

	local cache, evaluating = {}, {}
	local Evaluate

	local function Input( node, socket, fallback )
		local link = incoming[ node.id ] and incoming[ node.id ][ socket ]
		if not link then return fallback end
		return Evaluate( link.from.node, link.from.socket )
	end

	Evaluate = function( nodeID, socket )
		local key = nodeID .. "\1" .. socket
		if cache[ key ] then return cache[ key ] end
		if evaluating[ key ] then
			AddError( errors, "graph", "contains a cycle during evaluation" )
			return nil
		end
		evaluating[ key ] = true

		local node = nodes[ nodeID ]
		local result
		if not node then
			AddError( errors, "graph", "references missing node " .. tostring( nodeID ) )
		elseif node.type == "texture" then
			local map = node.params.texture
			if node.params.recipe then
				map = {
					source = node.params.texture, generated = true, ops = {},
					recipe = SafeRecipeCopy( node.params.recipe, "graph.nodes." .. node.id .. ".recipe", errors ),
				}
			end
			if socket == "color" then result = TextureValue( "color", map )
			elseif socket == "value" then result = TextureValue( "number", map )
			elseif socket == "normal" then result = TextureValue( "normal", map ) end
		elseif node.type == "value" and socket == "value" then
			result = Constant( "number", node.params.value )
		elseif node.type == "color" and socket == "color" then
			result = Constant( "color", CopyColor( node.params.color ) )
		elseif node.type == "invert" and socket == "value" then
			local input = Input( node, "value", Constant( "number", node.params.value ) )
			if input then
				if input.constant ~= nil then
					if input.value_type == "number" then
						result = Constant( "number", 1 - input.constant )
					elseif input.value_type == "color" then
						result = Constant( "color", {
							r = 1 - input.constant.r,
							g = 1 - input.constant.g,
							b = 1 - input.constant.b,
						} )
					end
				elseif input.map then
					local map = AppendMapOp( input.map, { op = "invert" }, errors,
						"graph.nodes." .. node.id )
					if map then result = TextureValue( input.value_type, map ) end
				end
			end
		elseif node.type == "multiply" and socket == "value" then
			local left  = Input( node, "a", Constant( "number", node.params.a ) )
			local right = Input( node, "b", Constant( "number", node.params.b ) )
			if left and right then
				local resultType = ( left.value_type == "color" or right.value_type == "color" )
					and "color" or "number"
				if left.constant ~= nil and right.constant ~= nil then
					if resultType == "number" then
						result = Constant( "number", left.constant * right.constant )
					else
						result = Constant( "color", MultiplyColor( left.constant, right.constant ) )
					end
				elseif left.map and right.map then
					AddError( errors, "graph.nodes." .. node.id,
						"cannot multiply two textures in one Remix material" )
				else
					local texture = left.map and left or right
					local constant = left.map and right or left
					local op
					if constant.value_type == "color" then
						op = { op = "multiply", color = CopyColor( constant.constant ) }
					else
						op = { op = "multiply", value = constant.constant }
					end
					local map = AppendMapOp( texture.map, op, errors, "graph.nodes." .. node.id )
					if map then result = TextureValue( resultType, map ) end
				end
			end
		elseif node.type == "normal_from_height" and socket == "normal" then
			local input = Input( node, "height", nil )
			if not input then
				AddError( errors, "graph.nodes." .. node.id .. ".height", "needs a texture input" )
			elseif not input.map then
				AddError( errors, "graph.nodes." .. node.id .. ".height",
					"cannot derive a normal map from a constant" )
			else
				local map = AppendMapOp( input.map, {
					op       = "normal_from_height",
					strength = node.params.strength,
					channel  = node.params.channel,
				}, errors, "graph.nodes." .. node.id )
				if map then result = TextureValue( "normal", map ) end
			end
		end

		evaluating[ key ] = nil
		cache[ key ] = result
		return result
	end

	local pbr = CopyPBR( clean.pbr )
	local bindings = {
		albedo              = { expected = "color",  map = "albedo",   constant = "albedo",
			neutral = { r = 1, g = 1, b = 1 } },
		normal              = { expected = "normal", map = "normal" },
		roughness           = { expected = "number", map = "roughness", constant = "roughness", neutral = 1 },
		metallic            = { expected = "number", map = "metallic",  constant = "metallic", neutral = 1 },
		height              = { expected = "number", map = "height" },
		emissive            = { expected = "color",  map = "emissive", constant = "emissive_color",
			neutral = { r = 1, g = 1, b = 1 } },
		emissive_intensity  = { expected = "number", constant = "emissive_intensity" },
		opacity             = { expected = "number", constant = "opacity" },
		anisotropy          = { expected = "number", map = "anisotropy",
			constant = "anisotropy", neutral = 0 },
		thin_film_thickness = { expected = "number", constant = "thin_film_thickness" },
		displace_in         = { expected = "number", constant = "displace_in" },
		displace_out        = { expected = "number", constant = "displace_out" },
		subsurface_transmittance = {
			expected = "color", map = "subsurface_transmittance",
			constant = "subsurface_transmittance_color",
			neutral = { r = 0.5, g = 0.5, b = 0.5 },
		},
		subsurface_thickness = {
			expected = "number", map = "subsurface_thickness",
			constant = "subsurface_measurement_distance", neutral = 0,
		},
		subsurface_scattering = {
			expected = "color", map = "subsurface_scattering",
			constant = "subsurface_single_scattering_albedo",
			neutral = { r = 0.5, g = 0.5, b = 0.5 },
		},
		subsurface_volumetric_anisotropy = {
			expected = "number", constant = "subsurface_volumetric_anisotropy",
		},
		subsurface_radius = {
			expected = "color", map = "subsurface_radius", constant = "subsurface_radius",
			neutral = { r = 0.5, g = 0.5, b = 0.5 },
		},
		subsurface_radius_scale = {
			expected = "number", constant = "subsurface_radius_scale",
		},
		subsurface_max_sample_radius = {
			expected = "number", constant = "subsurface_max_sample_radius",
		},
	}

	for socket, binding in pairs( bindings ) do
		local link = incoming[ output.id ] and incoming[ output.id ][ socket ]
		if link then
			local value = Evaluate( link.from.node, link.from.socket )
			if value then
				if value.value_type ~= binding.expected then
					AddError( errors, "graph.output." .. socket, "compiled to the wrong value type" )
				elseif value.map then
					if binding.map then
						pbr.maps[ binding.map ] = CopyKnownMap( value.map )
						-- A connected output is authoritative.  Neutralise the
						-- fallback constant so a stale direct control cannot tint
						-- or scale the graph's texture a second time.
						if binding.constant and binding.neutral ~= nil then
							pbr.constants[ binding.constant ] = IsTable( binding.neutral )
								and CopyColor( binding.neutral ) or binding.neutral
						end
					else
						AddError( errors, "graph.output." .. socket,
							"does not accept a texture in the Aperture PBR writer" )
					end
				elseif binding.constant then
					-- Same rule in the other direction: a constant graph output
					-- replaces, rather than silently combines with, a fallback map.
					if binding.map then pbr.maps[ binding.map ] = nil end
					local constant = value.constant
					if value.value_type == "color" then
						pbr.constants[ binding.constant ] = {
							r = Clamp( constant.r, 0, 1 ),
							g = Clamp( constant.g, 0, 1 ),
							b = Clamp( constant.b, 0, 1 ),
						}
					else
						local bounds = {
							roughness = { 0, 1 }, metallic = { 0, 1 }, opacity = { 0, 1 },
							emissive_intensity = { 0, 65504 }, anisotropy = { -1, 1 },
							thin_film_thickness = { 0, 1500 }, displace_in = { 0, 0.2 },
							displace_out = { 0, 0.2 },
							subsurface_measurement_distance = { 0, 16 },
							subsurface_volumetric_anisotropy = { -0.99, 0.99 },
							subsurface_radius_scale = { 0, 1000 },
							subsurface_max_sample_radius = { 0, 65504 },
						}
						local range = bounds[ binding.constant ] or { -1000000, 1000000 }
						pbr.constants[ binding.constant ] = Clamp( constant, range[ 1 ], range[ 2 ] )
					end
				end
			end
		elseif clean.graph.authoritative and clean.graph.authoritative[ socket ] then
			-- Once a surface socket has been edited in the graph, disconnecting or
			-- deleting its driver is an explicit clear.  Do not fall back to the
			-- stale pbr value from before the graph edit.
			if binding.map then pbr.maps[ binding.map ] = nil end
			if binding.constant then
				local default = S.DEFAULT_CONSTANTS[ binding.constant ]
				pbr.constants[ binding.constant ] = IsTable( default ) and CopyColor( default ) or default
			end
		end
	end

	-- Persisted USD inputs must name files the bundled writer can actually
	-- import.  Source/VTF logical names are valid editing sources only when a
	-- recipe will materialise them to a DATA-relative image first.
	local imageExtensions = {
		dds = true, png = true, jpg = true, jpeg = true, bmp = true,
		tif = true, tiff = true, gif = true,
	}
	for mapName, map in pairs( pbr.maps or {} ) do
		local source = type( map ) == "string" and map or ( map and map.source )
		local hasRecipe = type( map ) == "table" and map.recipe ~= nil
		local extension = type( source ) == "string"
			and string.match( string.lower( source ), "%.([%w]+)$" ) or nil
		if not hasRecipe and not imageExtensions[ extension ] then
			AddError( errors, "pbr.maps." .. tostring( mapName ),
				"must name a DDS/WIC image file or carry an edit/generator recipe" )
		end
	end

	if #errors > 0 then return nil, errors end
	local ruleID = S.RuleID( clean )
	local profileID = S.ProfileID( clean )
	return {
		version    = S.VERSION,
		target     = clean.target,
		rule_id    = ruleID,
		profile_id = profileID,
		pbr        = pbr,
	}, errors
end

S.CompileProfile = S.Compile

---------------------------------------------------------------------------
-- Editing helpers used by the RTX UI
---------------------------------------------------------------------------

local CONSTANT_BINDINGS = {
	albedo              = { socket = "albedo",              type = "color" },
	opacity             = { socket = "opacity",             type = "number" },
	roughness           = { socket = "roughness",           type = "number" },
	metallic            = { socket = "metallic",            type = "number" },
	emissive_color      = { socket = "emissive",            type = "color" },
	emissive_intensity  = { socket = "emissive_intensity",  type = "number" },
	anisotropy          = { socket = "anisotropy",          type = "number" },
	thin_film_thickness = { socket = "thin_film_thickness", type = "number" },
	displace_in         = { socket = "displace_in",         type = "number" },
	displace_out        = { socket = "displace_out",        type = "number" },
	subsurface_transmittance_color = { socket = "subsurface_transmittance", type = "color" },
	subsurface_measurement_distance = { socket = "subsurface_thickness", type = "number" },
	subsurface_single_scattering_albedo = { socket = "subsurface_scattering", type = "color" },
	subsurface_volumetric_anisotropy = { socket = "subsurface_volumetric_anisotropy", type = "number" },
	subsurface_radius = { socket = "subsurface_radius", type = "color" },
	subsurface_radius_scale = { socket = "subsurface_radius_scale", type = "number" },
	subsurface_max_sample_radius = { socket = "subsurface_max_sample_radius", type = "number" },
}

local MAP_BINDINGS = {
	albedo    = { socket = "albedo",    type = "color" },
	normal    = { socket = "normal",    type = "normal" },
	anisotropy = { socket = "anisotropy", type = "number" },
	roughness = { socket = "roughness", type = "number" },
	metallic  = { socket = "metallic",  type = "number" },
	height    = { socket = "height",    type = "number" },
	emissive  = { socket = "emissive",  type = "color" },
	subsurface_transmittance = { socket = "subsurface_transmittance", type = "color" },
	subsurface_thickness = { socket = "subsurface_thickness", type = "number" },
	subsurface_scattering = { socket = "subsurface_scattering", type = "color" },
	subsurface_radius = { socket = "subsurface_radius", type = "color" },
}

local EDIT_ORDER = {
	"albedo", "normal", "roughness", "metallic", "height", "emissive",
	"emissive_color", "emissive_intensity", "opacity", "anisotropy",
	"thin_film_thickness", "displace_in", "displace_out",
	"subsurface_transmittance", "subsurface_transmittance_color",
	"subsurface_thickness", "subsurface_measurement_distance",
	"subsurface_scattering", "subsurface_single_scattering_albedo",
	"subsurface_volumetric_anisotropy", "subsurface_radius",
	"subsurface_radius_scale", "subsurface_max_sample_radius",
}

local EDIT_ROW = {}
for index, key in ipairs( EDIT_ORDER ) do EDIT_ROW[ key ] = index end

local function CommitProfile( destination, clean )
	destination.version = clean.version
	destination.target  = clean.target
	destination.pbr     = clean.pbr
	destination.graph   = clean.graph
	return destination
end

local function InspectionPBR( inspection )
	if not IsTable( inspection ) then return {} end
	if IsTable( inspection.pbr ) then return inspection.pbr end
	if inspection.constants ~= nil or inspection.maps ~= nil or inspection.options ~= nil then
		return {
			constants = inspection.constants,
			maps      = inspection.maps,
			options   = inspection.options,
		}
	end

	-- The bridge's inspection record may mirror Remix's camelCase arguments.
	-- Translate those names here so the schema itself remains snake_case.
	local function First( left, right )
		if left ~= nil then return left end
		return right
	end

	local constants, maps, options = {}, {}, {}
	constants.albedo = First( inspection.albedo_constant, inspection.albedoConstant )
	constants.opacity = First( inspection.opacity_constant, inspection.opacityConstant )
	constants.roughness = First( inspection.roughness_constant, inspection.roughnessConstant )
	constants.metallic = First( inspection.metallic_constant, inspection.metallicConstant )
	constants.emissive_color = First( inspection.emissive_color, inspection.emissiveColorConstant )
	constants.emissive_intensity = First( inspection.emissive_intensity, inspection.emissiveIntensity )
	constants.anisotropy = inspection.anisotropy
	constants.thin_film_thickness = First( inspection.thin_film_thickness, inspection.thinFilmThickness )
	constants.displace_in = First( inspection.displace_in, inspection.displaceIn )
	constants.displace_out = First( inspection.displace_out, inspection.displaceOut )
	constants.subsurface_transmittance_color = First( inspection.subsurface_transmittance_color,
		inspection.subsurfaceTransmittanceColor )
	constants.subsurface_measurement_distance = First( inspection.subsurface_measurement_distance,
		inspection.subsurfaceMeasurementDistance )
	constants.subsurface_single_scattering_albedo = First(
		inspection.subsurface_single_scattering_albedo,
		inspection.subsurfaceSingleScatteringAlbedo )
	constants.subsurface_volumetric_anisotropy = First(
		inspection.subsurface_volumetric_anisotropy,
		inspection.subsurfaceVolumetricAnisotropy )
	constants.subsurface_radius = First( inspection.subsurface_radius,
		inspection.subsurfaceRadius )
	constants.subsurface_radius_scale = First( inspection.subsurface_radius_scale,
		inspection.subsurfaceRadiusScale )
	constants.subsurface_max_sample_radius = First( inspection.subsurface_max_sample_radius,
		inspection.subsurfaceMaxSampleRadius )

	maps.albedo = First( inspection.albedo_texture, inspection.albedoTexture )
	maps.normal = First( inspection.normal_texture, inspection.normalTexture )
	maps.anisotropy = First( inspection.anisotropy_texture, inspection.anisotropyTexture )
	maps.roughness = First( inspection.roughness_texture, inspection.roughnessTexture )
	maps.metallic = First( inspection.metallic_texture, inspection.metallicTexture )
	maps.height = First( inspection.height_texture, inspection.heightTexture )
	maps.emissive = First( inspection.emissive_texture, inspection.emissiveTexture )
	maps.subsurface_transmittance = First( inspection.subsurface_transmittance_texture,
		inspection.subsurfaceTransmittanceTexture )
	maps.subsurface_thickness = First( inspection.subsurface_thickness_texture,
		inspection.subsurfaceThicknessTexture )
	maps.subsurface_scattering = First( inspection.subsurface_single_scattering_texture,
		inspection.subsurfaceSingleScatteringTexture )
	maps.subsurface_radius = First( inspection.subsurface_radius_texture,
		inspection.subsurfaceRadiusTexture )

	options.filter_mode = First( inspection.filter_mode, inspection.filterMode )
	options.wrap_u = First( inspection.wrap_u, inspection.wrapModeU )
	options.wrap_v = First( inspection.wrap_v, inspection.wrapModeV )
	options.alpha_is_thin_film = First( inspection.alpha_is_thin_film,
		inspection.alphaIsThinFilmThickness )
	options.use_draw_call_alpha = First( inspection.use_draw_call_alpha,
		inspection.useDrawCallAlphaState )
	options.inverted_blend = First( inspection.inverted_blend, inspection.invertedBlend )
	options.blend_type = First( inspection.blend_type, inspection.blendType )
	options.alpha_test_type = First( inspection.alpha_test_type, inspection.alphaTestType )
	options.alpha_reference = First( inspection.alpha_reference, inspection.alphaReferenceValue )
	options.sprite_sheet_rows = First( inspection.sprite_sheet_rows,
		First( inspection.spriteSheetRows, inspection.spriteSheetRow ) )
	options.sprite_sheet_columns = First( inspection.sprite_sheet_columns,
		First( inspection.spriteSheetColumns, inspection.spriteSheetCol ) )
	options.sprite_sheet_fps = First( inspection.sprite_sheet_fps, inspection.spriteSheetFps )
	options.enable_thin_film = First( inspection.enable_thin_film, inspection.enableThinFilm )
	options.enable_emission = First( inspection.enable_emission, inspection.enableEmission )
	options.preload_textures = First( inspection.preload_textures, inspection.preloadTextures )
	options.ignore_material = First( inspection.ignore_material, inspection.ignoreMaterial )
	options.blend_enabled = First( inspection.blend_enabled, inspection.blendEnabled )
	options.normal_encoding = First( inspection.normal_encoding, inspection.normalEncoding )
	options.subsurface_diffusion_profile = First( inspection.subsurface_diffusion_profile,
		inspection.subsurfaceDiffusionProfile )

	return { constants = constants, maps = maps, options = options }
end

--- Create a clean version-one profile from a target and an optional normalized
--- or bridge-style inspection record.
function S.NewProfile( target, inspection )
	return S.Sanitize( {
		version = S.VERSION,
		target  = target,
		pbr     = InspectionPBR( inspection ),
		graph   = IsTable( inspection ) and inspection.graph or nil,
	} )
end

--- Make sure an in-progress profile has a valid graph.  Only a missing graph
--- is created; malformed user data is reported instead of silently erased.
function S.EnsureGraph( profile )
	local errors = {}
	if not IsTable( profile ) then
		AddError( errors, "profile", "must be a table" )
		return nil, errors
	end
	local graph = profile.graph
	if graph == nil then graph = S.DefaultGraph() end
	local clean, graphErrors = S.SanitizeGraph( graph )
	if not clean then return nil, graphErrors end
	profile.graph = clean
	return clean, graphErrors
end

local function FindOutputNode( graph )
	for _, node in ipairs( graph.nodes ) do
		if node.type == "output_surface" then return node end
	end
	return nil
end

local function RemoveIncomingLink( graph, nodeID, socket )
	for index = #graph.links, 1, -1 do
		local link = graph.links[ index ]
		if link.to.node == nodeID and link.to.socket == socket then table.remove( graph.links, index ) end
	end
end

local function RemoveGeneratedNodes( graph, prefix )
	local removed = {}
	for index = #graph.nodes, 1, -1 do
		local id = graph.nodes[ index ].id
		if id == prefix or string.sub( id, 1, #prefix + 1 ) == prefix .. "_" then
			removed[ id ] = true
			table.remove( graph.nodes, index )
		end
	end
	for index = #graph.links, 1, -1 do
		local link = graph.links[ index ]
		if removed[ link.from.node ] or removed[ link.to.node ] then table.remove( graph.links, index ) end
	end
end

local function AddLink( graph, fromNode, fromSocket, toNode, toSocket )
	graph.links[ #graph.links + 1 ] = {
		from = { node = fromNode, socket = fromSocket },
		to   = { node = toNode, socket = toSocket },
	}
end

local function NodePosition( output, key, stage )
	return ( output.x or 640 ) - 480 + stage * 145,
		( output.y or 240 ) + ( ( EDIT_ROW[ key ] or 1 ) - 1 ) * 28
end

--- Set a surface constant through a deterministic source node.  The graph
--- remains authoritative: any previous link into that output socket is
--- replaced, while unrelated custom nodes are left untouched.
function S.SetConstant( profile, key, value )
	local binding = CONSTANT_BINDINGS[ key ]
	if not binding then return nil, { "constant: is not allowlisted" } end
	local clean, errors = S.Sanitize( profile )
	if not clean then return nil, errors end

	local output = FindOutputNode( clean.graph )
	clean.graph.authoritative = clean.graph.authoritative or {}
	clean.graph.authoritative[ binding.socket ] = true
	local prefix = "advmat_direct_c_" .. key
	RemoveGeneratedNodes( clean.graph, prefix )
	RemoveIncomingLink( clean.graph, output.id, binding.socket )

	clean.pbr.constants[ key ] = value
	local x, y = NodePosition( output, key, 0 )
	local node
	local fromSocket
	if binding.type == "color" then
		node = { id = prefix, type = "color", x = x, y = y, params = { color = value } }
		fromSocket = "color"
	else
		node = { id = prefix, type = "value", x = x, y = y, params = { value = value } }
		fromSocket = "value"
	end
	clean.graph.nodes[ #clean.graph.nodes + 1 ] = node
	AddLink( clean.graph, node.id, fromSocket, output.id, binding.socket )

	local finished, finishErrors = S.Sanitize( clean )
	if not finished then return nil, finishErrors end
	return CommitProfile( profile, finished ), finishErrors
end

--- Set or clear a surface texture.  Bake descriptors are expanded into the
--- same small graph language used by the canvas, so reopening a profile never
--- shows a hidden operation that exists only in a side table.
function S.SetMap( profile, key, value )
	local binding = MAP_BINDINGS[ key ]
	if not binding then return nil, { "map: is not allowlisted" } end
	local clean, errors = S.Sanitize( profile )
	if not clean then return nil, errors end

	local output = FindOutputNode( clean.graph )
	clean.graph.authoritative = clean.graph.authoritative or {}
	local prefix = "advmat_direct_m_" .. key
	RemoveGeneratedNodes( clean.graph, prefix )
	RemoveIncomingLink( clean.graph, output.id, binding.socket )

	if value == nil or value == "" then
		clean.pbr.maps[ key ] = nil
		-- The surface panel's Clear action deliberately reveals the matching
		-- fallback constant.  A canvas disconnect remains authoritative because
		-- the node panel leaves this marker set when it removes a wire.
		clean.graph.authoritative[ binding.socket ] = nil
		local finished, finishErrors = S.Sanitize( clean )
		if not finished then return nil, finishErrors end
		return CommitProfile( profile, finished ), finishErrors
	end

	local map, mapErrors = S.SanitizeMap( value )
	if not map then return nil, mapErrors end
	clean.graph.authoritative[ binding.socket ] = true
	clean.pbr.maps[ key ] = map

	local descriptor = type( map ) == "string" and { source = map, ops = {} } or map
	local hasNormalConversion = false
	for _, op in ipairs( descriptor.ops or {} ) do
		if op.op == "normal_from_height" then hasNormalConversion = true break end
	end
	local valueType = hasNormalConversion and "number" or binding.type
	local fromSocket = valueType == "color" and "color" or
		( valueType == "normal" and "normal" or "value" )
	local x, y = NodePosition( output, key, 0 )
	local previous = prefix
	clean.graph.nodes[ #clean.graph.nodes + 1 ] = {
		id = previous, type = "texture", x = x, y = y,
		params = { texture = descriptor.source, recipe = descriptor.recipe },
	}

	for index, op in ipairs( descriptor.ops or {} ) do
		local opID = prefix .. "_op" .. index
		x, y = NodePosition( output, key, index )
		if op.op == "invert" then
			if valueType ~= "number" and valueType ~= "color" then
				return nil, { "map.ops[" .. index .. "]: cannot invert a " .. valueType .. " map" }
			end
			clean.graph.nodes[ #clean.graph.nodes + 1 ] = {
				id = opID, type = "invert", x = x, y = y, params = {},
			}
			AddLink( clean.graph, previous, fromSocket, opID, "value" )
			previous, fromSocket = opID, "value"
		elseif op.op == "multiply" then
			if valueType ~= "number" and valueType ~= "color" then
				return nil, { "map.ops[" .. index .. "]: cannot multiply a " .. valueType .. " map" }
			end
			local argID = prefix .. "_arg" .. index
			local argType, argSocket, params
			if op.color then
				argType, argSocket, params = "color", "color", { color = op.color }
				valueType = "color"
			else
				argType, argSocket, params = "value", "value", { value = op.value }
			end
			clean.graph.nodes[ #clean.graph.nodes + 1 ] = {
				id = argID, type = argType, x = x, y = y + 70, params = params,
			}
			clean.graph.nodes[ #clean.graph.nodes + 1 ] = {
				id = opID, type = "multiply", x = x, y = y, params = {},
			}
			AddLink( clean.graph, previous, fromSocket, opID, "a" )
			AddLink( clean.graph, argID, argSocket, opID, "b" )
			previous, fromSocket = opID, "value"
		elseif op.op == "normal_from_height" then
			if valueType ~= "number" then
				return nil, { "map.ops[" .. index .. "]: normal-from-height needs a scalar map" }
			end
			clean.graph.nodes[ #clean.graph.nodes + 1 ] = {
				id = opID, type = "normal_from_height", x = x, y = y,
				params = { strength = op.strength, channel = op.channel },
			}
			AddLink( clean.graph, previous, fromSocket, opID, "height" )
			previous, fromSocket, valueType = opID, "normal", "normal"
		end
	end

	if valueType ~= binding.type then
		return nil, { "map: operations compile to " .. valueType .. ", expected " .. binding.type }
	end
	AddLink( clean.graph, previous, fromSocket, output.id, binding.socket )

	local finished, finishErrors = S.Sanitize( clean )
	if not finished then return nil, finishErrors end
	return CommitProfile( profile, finished ), finishErrors
end

--- The authoritative material state after all graph connections have been
--- evaluated.  This is the table the bridge turns into Remix API arguments.
function S.GetEffectivePBR( profile )
	local compiled, errors = S.Compile( profile )
	if not compiled then return nil, errors end
	return compiled.pbr, errors
end
