-- Deterministic damage-scaled removal-hull shapes shared by querying,
-- projection, diagnostics, and retained-hit rendering.

BBS = BBS or {}

local TWO_PI = math.pi * 2
local RANDOM_MODULUS = 2147483647

-- The fallback is only for a setting that does not exist: "convar and
-- convar:GetBool() or fallback" would turn a setting of 0 into the fallback.
local function GetBool( name, fallback )
	local convar = GetConVar( name )
	if not convar then return fallback end
	return convar:GetBool()
end

local function GetFloat( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetFloat() or fallback
end

local function GetInt( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetInt() or fallback
end

local function PositiveModulo( value, divisor )
	return ( ( value % divisor ) + divisor ) % divisor
end

local function Atan2( y, x )
	if math.atan2 then return math.atan2( y, x ) end
	if x > 0 then return math.atan( y / x ) end
	if x < 0 then
		return math.atan( y / x ) + ( y >= 0 and math.pi or -math.pi )
	end
	if y > 0 then return math.pi * 0.5 end
	if y < 0 then return -math.pi * 0.5 end
	return 0
end

local function HashSeed( text )
	local hash = 5381
	for index = 1, #text do
		hash = ( hash * 33 + string.byte( text, index ) ) % RANDOM_MODULUS
	end
	return math.max( math.floor( hash ), 1 )
end

local function NewRandom( seed )
	seed = math.Clamp( math.floor( tonumber( seed ) or 1 ), 1, RANDOM_MODULUS - 1 )
	return function()
		-- Park-Miller keeps all intermediate values exactly representable by the
		-- Lua number type and does not disturb Lua's process-global RNG state.
		seed = ( seed * 16807 ) % RANDOM_MODULUS
		return ( seed - 1 ) / ( RANDOM_MODULUS - 1 )
	end
end

local function StablePerpendicular( axis, preferredRight )
	if isvector( preferredRight ) then
		local projected = preferredRight - axis * preferredRight:Dot( axis )
		if projected:LengthSqr() > 0.000001 then return projected:GetNormalized() end
	end
	local reference = math.abs( axis.z ) < 0.95
		and Vector( 0, 0, 1 ) or Vector( 0, 1, 0 )
	return axis:Cross( reference ):GetNormalized()
end

function BBS.BuildRemovalHullFrame( origin, hitDirection, surfaceNormal,
	parameters, preferredRight )
	if not isvector( origin ) or not isvector( hitDirection )
	or hitDirection:IsZero() then return nil end
	local axis = hitDirection:GetNormalized()
	if isvector( surfaceNormal ) and axis:Dot( surfaceNormal ) > 0 then axis = -axis end
	parameters = parameters or {}
	local right = StablePerpendicular( axis, preferredRight or parameters.right )
	local up = right:Cross( axis ):GetNormalized()
	local maximumAngularSlope = tonumber( parameters.maximumAngularSlope )
	local radii = parameters.radii
	if maximumAngularSlope == nil and radii and #radii >= 2 then
		maximumAngularSlope = 0
		local angularStep = TWO_PI / #radii
		for index = 1, #radii do
			local following = index % #radii + 1
			maximumAngularSlope = math.max( maximumAngularSlope,
				math.abs( ( tonumber( radii[ following ] ) or 0 )
					- ( tonumber( radii[ index ] ) or 0 ) ) / angularStep )
		end
	end
	return {
		origin = origin,
		axis = axis,
		right = right,
		up = up,
		parameters = parameters,
		insideDistance = math.max( tonumber( parameters.insideDistance ) or 0, 0 ),
		outsideDistance = math.max( tonumber( parameters.outsideDistance ) or 0, 0 ),
		minimumRadius = math.max( tonumber( parameters.minimumRadius )
			or tonumber( parameters.radius ) or 0.05, 0.0001 ),
		maximumRadius = math.max( tonumber( parameters.maximumRadius )
			or tonumber( parameters.radius ) or 0.05, 0.0001 ),
		-- The polar boundary is piecewise linear between samples. Its largest
		-- radius change per radian is a global Lipschitz bound used by adaptive
		-- UV projection to reject/accept cells without missing narrow tears.
		maximumAngularSlope = math.max(
			maximumAngularSlope or 0, 0 ),
	}
end

function BBS.RemovalHullRadiusAtAngle( frame, radians )
	local parameters = frame and frame.parameters or {}
	local radii = parameters.radii
	local count = radii and #radii or 0
	if count < 2 then return math.max( tonumber( parameters.radius ) or 0.05, 0.0001 ) end
	local offset = tonumber( parameters.angleOffset ) or 0
	local coordinate = PositiveModulo( radians - offset, TWO_PI ) / TWO_PI * count
	local lowerZero = math.floor( coordinate )
	local fraction = coordinate - lowerZero
	local lower = lowerZero + 1
	local upper = lower % count + 1
	return radii[ lower ] + ( radii[ upper ] - radii[ lower ] ) * fraction
end

function BBS.RemovalHullPointData( frame, point )
	-- Scalar arithmetic avoids constructing a temporary Vector for every
	-- adaptive projection sample. This function is called many thousands of
	-- times by a detailed hit.
	local dx = point.x - frame.origin.x
	local dy = point.y - frame.origin.y
	local dz = point.z - frame.origin.z
	local axis, right, up = frame.axis, frame.right, frame.up
	local axial = dx * axis.x + dy * axis.y + dz * axis.z
	local radialX = dx * right.x + dy * right.y + dz * right.z
	local radialY = dx * up.x + dy * up.y + dz * up.z
	local radial = math.sqrt( radialX * radialX + radialY * radialY )
	local angle = Atan2( radialY, radialX )
	local boundaryRadius = BBS.RemovalHullRadiusAtAngle( frame, angle )
	return axial, radial, angle, boundaryRadius
end

function BBS.RemovalHullSignedValue( frame, point )
	local axial, radial, _, boundaryRadius = BBS.RemovalHullPointData( frame, point )
	local radialValue = radial - boundaryRadius
	local axialValue = math.max(
		axial - frame.insideDistance, -frame.outsideDistance - axial )
	-- This has the correct sign for clipping. Adaptive pruning separately uses
	-- the conservative global min/max radii and does not assume this is an exact
	-- Euclidean signed-distance field for the jagged polar boundary.
	return math.max( radialValue, axialValue ), axial, radial, boundaryRadius
end

function BBS.PointInsideRemovalHull( frame, point )
	return frame and BBS.RemovalHullSignedValue( frame, point ) <= 0 or false
end

function BBS.BuildDamageHullParameters( hit, baseRadius, insideDistance,
	outsideDistance )
	local damage = math.max( tonumber( hit and hit.damage ) or 0, 0 )
	local referenceDamage = math.Clamp(
		GetFloat( "bbs_hole_reference_damage", 5 ), 0.1, 500 )
	local maximumMultiplier = math.Clamp(
		GetFloat( "bbs_hole_max_radius_multiplier", 5 ), 1, 12 )
	local scalingEnabled = GetBool( "bbs_hole_damage_scaling", true )
	local scalingDamage = damage > 0 and damage or referenceDamage
	local rawMultiplier = scalingEnabled
		and math.sqrt( scalingDamage / referenceDamage ) or 1
	local sizeMultiplier = math.Clamp( rawMultiplier, 0.5, maximumMultiplier )
	baseRadius = math.Clamp( tonumber( baseRadius ) or 0.5, 0.05, 256 )
	local nominalRadius = baseRadius * sizeMultiplier
	local maximumAllowedRadius = baseRadius * maximumMultiplier

	local baseIrregularity = math.Clamp(
		GetFloat( "bbs_hole_base_irregularity", 0.4 ), 0, 0.75 )
	local damageIrregularity = math.Clamp(
		GetFloat( "bbs_hole_damage_irregularity", 0.5 ), 0, 0.75 )
	local maximumIrregularity = math.Clamp(
		GetFloat( "bbs_hole_max_irregularity", 0.9 ), 0, 0.9 )
	local irregularityMultiplier = scalingEnabled and rawMultiplier or 1
	local irregularity = math.Clamp( baseIrregularity
		+ damageIrregularity * math.max( irregularityMultiplier - 1, 0 ),
		0, maximumIrregularity )
	local sampleCount = math.Clamp( GetInt( "bbs_hole_shape_samples", 24 ), 8, 64 )

	local position = hit and hit.surfacePosition or Vector( 0, 0, 0 )
	local seedText = string.format( "%d|%d|%.3f|%.3f|%.3f|%.3f",
		hit and hit.serial or 0, hit and hit.entityIndex or -1,
		position.x, position.y, position.z, damage )
	local seed = HashSeed( seedText )
	local random = NewRandom( seed )
	local angleOffset = random() * TWO_PI
	local phaseTwo = random() * TWO_PI
	local phaseThree = random() * TWO_PI
	local rawNoise = {}
	for index = 1, sampleCount do rawNoise[ index ] = random() * 2 - 1 end

	local factors = {}
	for index = 1, sampleCount do
		local previous = rawNoise[ ( index - 2 ) % sampleCount + 1 ]
		local current = rawNoise[ index ]
		local following = rawNoise[ index % sampleCount + 1 ]
		local smoothed = previous * 0.2 + current * 0.6 + following * 0.2
		local angle = ( index - 1 ) / sampleCount * TWO_PI
		local lowFrequency = math.sin( angle * 2 + phaseTwo ) * 0.25
			+ math.sin( angle * 3 + phaseThree ) * 0.16
		factors[ index ] = 1 + irregularity * ( smoothed * 0.65 + lowFrequency )
	end

	-- Localized peaks/notches create cloth-like radial tears rather than a
	-- uniformly noisy circle. More damage raises irregularity and therefore
	-- both their count and amplitude.
	local tearCount = math.Clamp( math.floor( 1 + irregularity * 8 + random() * 2 ),
		1, math.max( math.floor( sampleCount / 4 ), 1 ) )
	for tear = 1, tearCount do
		local center = math.floor( random() * sampleCount ) + 1
		local width = 1 + math.floor( random() * 2 )
		local sign = random() < 0.72 and 1 or -1
		local amplitude = irregularity * ( 0.45 + random() * 0.9 ) * sign
		for offset = -width, width do
			local index = ( center + offset - 1 ) % sampleCount + 1
			local weight = 1 - math.abs( offset ) / ( width + 1 )
			factors[ index ] = factors[ index ] + amplitude * weight
		end
	end

	local factorTotal = 0
	for _, factor in ipairs( factors ) do factorTotal = factorTotal + factor end
	local factorAverage = factorTotal / sampleCount
	local minimumFactor = math.max( 1 - irregularity * 1.6, 0.25 )
	local maximumFactor = 1 + irregularity * 2.1
	local radii = {}
	local minimumRadius = math.huge
	local maximumRadius = 0
	for index, factor in ipairs( factors ) do
		factor = math.Clamp( factor / math.max( factorAverage, 0.001 ),
			minimumFactor, maximumFactor )
		local radius = math.Clamp( nominalRadius * factor,
			baseRadius * 0.125, maximumAllowedRadius )
		radii[ index ] = radius
		minimumRadius = math.min( minimumRadius, radius )
		maximumRadius = math.max( maximumRadius, radius )
	end
	local angularStep = TWO_PI / sampleCount
	local maximumAngularSlope = 0
	for index = 1, sampleCount do
		local following = index % sampleCount + 1
		maximumAngularSlope = math.max( maximumAngularSlope,
			math.abs( radii[ following ] - radii[ index ] ) / angularStep )
	end

	local initialFrame = BBS.BuildRemovalHullFrame( position,
		hit and hit.direction or Vector( 1, 0, 0 ),
		hit and hit.normal or nil, {} )
	return {
		baseRadius = baseRadius,
		radius = nominalRadius,
		minimumRadius = minimumRadius,
		maximumRadius = maximumRadius,
		maximumAngularSlope = maximumAngularSlope,
		insideDistance = math.Clamp( tonumber( insideDistance ) or 1, 0, 512 ),
		outsideDistance = math.Clamp( tonumber( outsideDistance ) or 2, 0, 512 ),
		damage = damage,
		referenceDamage = referenceDamage,
		damageScaling = scalingEnabled,
		damageMultiplier = sizeMultiplier,
		maximumDamageMultiplier = maximumMultiplier,
		irregularity = irregularity,
		baseIrregularity = baseIrregularity,
		damageIrregularity = damageIrregularity,
		maximumIrregularity = maximumIrregularity,
		shapeSamples = sampleCount,
		tearCount = tearCount,
		seed = seed,
		angleOffset = angleOffset,
		radii = radii,
		right = initialFrame and initialFrame.right or nil,
	}
end
