--[[---------------------------------------------------------------------------
	Advanced Material Editor - shared utility / value marshalling

	Everything that crosses the network or hits the disk is stored as VMT
	literal STRINGS, exactly the way they would appear in a .vmt file. The UI
	layer is the only place that converts to and from numbers, booleans and
	colours. That keeps the store format identical to what CreateMaterial
	expects and makes the on-disk database human readable.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

---------------------------------------------------------------------------
-- Path normalisation
---------------------------------------------------------------------------

--- "materials/Models/Foo/Bar.vmt" -> "models/foo/bar"
function AdvMat.NormalizeMaterial( path )
	if not isstring( path ) then return "" end
	path = string.lower( string.Trim( path ) )
	path = string.gsub( path, "\\", "/" )
	path = string.gsub( path, "^materials/", "" )
	path = string.gsub( path, "%.vmt$", "" )
	path = string.gsub( path, "%.vtf$", "" )
	return path
end

--- "models/Foo/Bar.mdl" -> "models/foo/bar.mdl"
function AdvMat.NormalizeModel( mdl )
	if not isstring( mdl ) then return "" end
	mdl = string.lower( string.Trim( mdl ) )
	mdl = string.gsub( mdl, "\\", "/" )
	return mdl
end

---------------------------------------------------------------------------
-- VMT value marshalling
---------------------------------------------------------------------------

--- Format a number the way a .vmt would: trim pointless trailing zeroes.
function AdvMat.NumToString( n )
	if not isnumber( n ) then return tostring( n ) end
	if n == math.floor( n ) and math.abs( n ) < 1e9 then
		return string.format( "%d", n )
	end
	local s = string.format( "%.6f", n )
	s = string.gsub( s, "0+$", "" )
	s = string.gsub( s, "%.$", "" )
	return s
end

--- Vector -> "[1 0.5 0]"
function AdvMat.VectorToString( v )
	return "[" .. AdvMat.NumToString( v.x ) .. " "
	           .. AdvMat.NumToString( v.y ) .. " "
	           .. AdvMat.NumToString( v.z ) .. "]"
end

--- util.JSONToTable treats any "{x y z}" string as an Angle. VMT uses that
--- exact syntax for 0-255 colour vectors, so turn the automatic conversion
--- back into its literal form before a rule is stored or built.
function AdvMat.AngleToVMTString( a )
	return "{" .. AdvMat.NumToString( a.p ) .. " "
	           .. AdvMat.NumToString( a.y ) .. " "
	           .. AdvMat.NumToString( a.r ) .. "}"
end

--- Accepts "[1 .5 0]", "{255 128 0}", "1 .5 0", "0.5" -> Vector
function AdvMat.StringToVector( s, fallback )
	fallback = fallback or Vector( 1, 1, 1 )
	if isvector( s ) then return Vector( s ) end
	if isnumber( s ) then return Vector( s, s, s ) end
	if not isstring( s ) then return fallback end

	local body   = string.Trim( s )
	local is255  = string.sub( body, 1, 1 ) == "{"
	body = string.gsub( body, "[%[%]{}]", " " )

	local nums = {}
	for tok in string.gmatch( body, "[-%d%.eE+]+" ) do
		nums[ #nums + 1 ] = tonumber( tok )
	end

	if #nums == 0 then return fallback end
	if #nums == 1 then return Vector( nums[1], nums[1], nums[1] ) end

	local v = Vector( nums[1] or 0, nums[2] or 0, nums[3] or 0 )
	if is255 then v = v / 255 end
	return v
end

--- A VMT literal the way it looks after a trip through the network. GMod's
--- util.JSONToTable turns a string shaped like "[x y z]" into a Vector and
--- "{x y z}" into an Angle, and SanitizeParams writes those back out in its own
--- spelling, so "[1.0 .5 0]" arrives as "[1 0.5 0]". Anything comparing a value
--- that crossed the network with one that did not puts both through this.
function AdvMat.WireValue( s )
	if not isstring( s ) then return s end

	local body, angle = string.match( s, "^%s*%[(.-)%]%s*$" ), false
	if not body then
		body, angle = string.match( s, "^%s*{(.-)}%s*$" ), true
	end
	if not body then return s end

	local nums = {}
	for token in string.gmatch( body, "[-%d%.eE+]+" ) do
		nums[ #nums + 1 ] = tonumber( token )
	end
	if #nums ~= 3 or not nums[ 1 ] or not nums[ 2 ] or not nums[ 3 ] then return s end

	if angle then return AdvMat.AngleToVMTString( Angle( nums[ 1 ], nums[ 2 ], nums[ 3 ] ) ) end
	return AdvMat.VectorToString( Vector( nums[ 1 ], nums[ 2 ], nums[ 3 ] ) )
end

--- Turn anything IMaterial:GetKeyValues() can hand back into a VMT literal.
function AdvMat.ToVMTString( v )
	local t = TypeID( v )

	if isstring( v )  then return v end
	if isnumber( v )  then return AdvMat.NumToString( v ) end
	if isbool( v )    then return v and "1" or "0" end
	if isvector( v )  then return AdvMat.VectorToString( v ) end
	if isangle and isangle( v ) then return AdvMat.AngleToVMTString( v ) end

	-- ITexture
	if t == TYPE_TEXTURE then
		local name = v:GetName()
		return name and AdvMat.NormalizeMaterial( name ) or ""
	end

	-- VMatrix (texture transforms). There is no reliable way to reconstruct
	-- the original "center .5 .5 scale 1 1 rotate 0 translate 0 0" text from a
	-- VMatrix, so transforms are stored as text and only ever written, never
	-- read back out of a live material.
	if t == TYPE_MATRIX then return nil end

	if v == nil then return nil end
	return tostring( v )
end

---------------------------------------------------------------------------
-- Texture transforms
---------------------------------------------------------------------------
-- "center .5 .5 scale 1 1 rotate 0 translate 0 0" - the string form every
-- transform parameter takes. Parsed into named fields so the editor can put
-- sliders in front of it instead of a line of text.

AdvMat.TRANSFORM_DEFAULT = { cx = 0.5, cy = 0.5, sx = 1, sy = 1, rot = 0, tx = 0, ty = 0 }

function AdvMat.ParseTransform( s )
	local t = {}
	for k, v in pairs( AdvMat.TRANSFORM_DEFAULT ) do t[ k ] = v end

	if not isstring( s ) then return t end

	local num = "([-%d%.eE+]+)"

	local cx, cy = string.match( s, "center%s+" .. num .. "%s+" .. num )
	if cx then t.cx, t.cy = tonumber( cx ) or t.cx, tonumber( cy ) or t.cy end

	local sx, sy = string.match( s, "scale%s+" .. num .. "%s+" .. num )
	if sx then t.sx, t.sy = tonumber( sx ) or t.sx, tonumber( sy ) or t.sy end

	local rot = string.match( s, "rotate%s+" .. num )
	if rot then t.rot = tonumber( rot ) or t.rot end

	local tx, ty = string.match( s, "translate%s+" .. num .. "%s+" .. num )
	if tx then t.tx, t.ty = tonumber( tx ) or t.tx, tonumber( ty ) or t.ty end

	return t
end

function AdvMat.TransformToString( t )
	local n = AdvMat.NumToString

	return "center "     .. n( t.cx )  .. " " .. n( t.cy )
	    .. " scale "     .. n( t.sx )  .. " " .. n( t.sy )
	    .. " rotate "    .. n( t.rot )
	    .. " translate " .. n( t.tx )  .. " " .. n( t.ty )
end

--- True when a transform leaves the texture exactly where it started.
function AdvMat.TransformIsIdentity( t )
	local d = AdvMat.TRANSFORM_DEFAULT
	for k, v in pairs( d ) do
		if math.abs( ( t[ k ] or v ) - v ) > 0.0001 then return false end
	end
	return true
end

--- Short human form, e.g. "scale 2 2   rotate 45".
function AdvMat.TransformSummary( t )
	if AdvMat.TransformIsIdentity( t ) then return "no transform" end

	local n     = AdvMat.NumToString
	local d     = AdvMat.TRANSFORM_DEFAULT
	local parts = {}

	if t.sx ~= d.sx or t.sy ~= d.sy then
		parts[ #parts + 1 ] = "scale " .. n( t.sx ) .. " " .. n( t.sy )
	end
	if t.rot ~= d.rot then parts[ #parts + 1 ] = "rotate " .. n( t.rot ) end
	if t.tx ~= d.tx or t.ty ~= d.ty then
		parts[ #parts + 1 ] = "slide " .. n( t.tx ) .. " " .. n( t.ty )
	end
	if t.cx ~= d.cx or t.cy ~= d.cy then
		parts[ #parts + 1 ] = "pivot " .. n( t.cx ) .. " " .. n( t.cy )
	end

	return table.concat( parts, "   " )
end

---------------------------------------------------------------------------
-- Keys that must never be round-tripped back into CreateMaterial
---------------------------------------------------------------------------
-- GetKeyValues() exposes engine-internal bitfields. Feeding them back in
-- produces materials with corrupted flag state (invisible / fullbright /
-- untextured), so they are dropped when a material is rebuilt.
AdvMat.INTERNAL_KEYS = {
	[ "$flags" ]           = true,
	[ "$flags_defined" ]   = true,
	[ "$flags2" ]          = true,
	[ "$flags_defined2" ]  = true,
	[ "$flagsdefined" ]    = true,
	[ "$flagsdefined2" ]   = true,
}

function AdvMat.IsInternalKey( k )
	if AdvMat.INTERNAL_KEYS[ k ] then return true end
	return false
end

---------------------------------------------------------------------------
-- Rule identity
---------------------------------------------------------------------------

--- Stable string id for a rule, used as the table key in the store.
function AdvMat.RuleID( scope, key, index )
	if scope == AdvMat.SCOPE.WORLD then
		return "wld:" .. AdvMat.NormalizeMaterial( key )
	elseif scope == AdvMat.SCOPE.MATERIAL then
		return "mat:" .. AdvMat.NormalizeMaterial( key )
	elseif scope == AdvMat.SCOPE.MODEL then
		return "mdl:" .. AdvMat.NormalizeModel( key ) .. ":" .. tostring( tonumber( index ) or 0 )
	end
	return "ent:" .. tostring( key ) .. ":" .. tostring( tonumber( index ) or 0 )
end

--- True when a rule (or an editor working copy, which has the same shape)
--- carries no edit at all.
---
--- A shader override counts on its own. Testing only the parameter table meant
--- that picking a different shader and changing nothing else was invisible to
--- the preview, the sub-material list and the save.
function AdvMat.RuleIsEmpty( rule )
	if not istable( rule ) then return true end
	if isstring( rule.shader ) and rule.shader ~= "" then return false end
	return table.IsEmpty( rule.params or {} )
end

--- Shallow copy of a params table with non-string values coerced and blanks
--- dropped. Also enforces sane key/value sizes so a malicious client cannot
--- push megabytes of junk into the persistent store.
function AdvMat.SanitizeParams( params )
	local out, count = {}, 0
	if not istable( params ) then return out end

	for rawKey, v in pairs( params ) do
		if isstring( rawKey ) and count < 256 then
			local k     = string.lower( string.Trim( rawKey ) )
			local sigil = string.sub( k, 1, 1 )
			if ( sigil == "$" or sigil == "%" ) and #k <= 64 and not AdvMat.IsInternalKey( k ) then
				local s = AdvMat.ToVMTString( v )
				if isstring( s ) then
					s = string.Trim( s )
					if #s > 0 and #s <= 256 then
						out[ k ] = s
						count = count + 1
					end
				end
			end
		end
	end

	return out
end

--- Coerce a value from anywhere - a slider, a preset file, a table that
--- arrived over the network - into a number inside a range.
---
--- The NaN test is the point of it. math.Clamp is two comparisons, and every
--- comparison against NaN is false, so a NaN passes through a clamp untouched
--- and then propagates through every calculation downstream until something
--- indexes an array with it.
function AdvMat.ClampNum( v, lo, hi, fallback )
	local n = tonumber( v )
	if not n or n ~= n then return fallback end
	return math.Clamp( n, lo, hi )
end

function AdvMat.TableCount( t )
	local n = 0
	if istable( t ) then for _ in pairs( t ) do n = n + 1 end end
	return n
end

---------------------------------------------------------------------------
-- Hashing
---------------------------------------------------------------------------
-- Hashes here name things that more than one machine has to agree on: the
-- procedural material a server hands out, the file a generated texture is
-- cached under. Feature-detecting the strongest available hash is therefore
-- not valid - util.SHA1 is missing on some branches - and every branch must
-- produce the same digest. The engine's SHA-1 is used only after it has given
-- the standard answer for "abc"; otherwise a pure-Lua SHA-1 produces the
-- identical digest.
local function Unsigned32( value )
	value = tonumber( value ) or 0
	if value < 0 then value = value + 4294967296 end
	return value % 4294967296
end

local function PackU32( value )
	value = Unsigned32( value )
	return string.char(
		math.floor( value / 16777216 ) % 256,
		math.floor( value / 65536 ) % 256,
		math.floor( value / 256 ) % 256,
		value % 256 )
end

local function RotateLeft( value, amount )
	if bit.rol then return bit.rol( value, amount ) end
	return bit.bor( bit.lshift( value, amount ), bit.rshift( value, 32 - amount ) )
end

local function PureSHA1( source )
	local bytes = #source
	local lowBits = ( bytes * 8 ) % 4294967296
	local highBits = math.floor( bytes / 536870912 )
	local zeroes = ( 56 - ( bytes + 1 ) % 64 ) % 64
	local data = source .. "\128" .. string.rep( "\0", zeroes )
		.. PackU32( highBits ) .. PackU32( lowBits )

	local h0, h1, h2, h3, h4 =
		0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
	local words = {}
	for offset = 1, #data, 64 do
		for index = 0, 15 do
			local at = offset + index * 4
			local a, b, c, d = string.byte( data, at, at + 3 )
			words[ index ] = ( ( ( a * 256 + b ) * 256 + c ) * 256 + d )
		end
		for index = 16, 79 do
			words[ index ] = RotateLeft( bit.bxor( words[ index - 3 ],
				words[ index - 8 ], words[ index - 14 ], words[ index - 16 ] ), 1 )
		end

		local a, b, c, d, e = h0, h1, h2, h3, h4
		for index = 0, 79 do
			local f, constant
			if index < 20 then
				-- XOR with all ones is the portable 32-bit complement; a few
				-- older/test bit libraries omit the otherwise equivalent bnot.
				f = bit.bor( bit.band( b, c ),
					bit.band( bit.bxor( b, 0xFFFFFFFF ), d ) )
				constant = 0x5A827999
			elseif index < 40 then
				f = bit.bxor( b, c, d )
				constant = 0x6ED9EBA1
			elseif index < 60 then
				f = bit.bor( bit.band( b, c ), bit.band( b, d ), bit.band( c, d ) )
				constant = 0x8F1BBCDC
			else
				f = bit.bxor( b, c, d )
				constant = 0xCA62C1D6
			end
			local nextA = bit.band( RotateLeft( a, 5 ) + f + e + constant + words[ index ],
				0xFFFFFFFF )
			e, d, c, b, a = d, c, RotateLeft( b, 30 ), a, nextA
		end

		h0 = bit.band( h0 + a, 0xFFFFFFFF )
		h1 = bit.band( h1 + b, 0xFFFFFFFF )
		h2 = bit.band( h2 + c, 0xFFFFFFFF )
		h3 = bit.band( h3 + d, 0xFFFFFFFF )
		h4 = bit.band( h4 + e, 0xFFFFFFFF )
	end

	return string.format( "%08x%08x%08x%08x%08x",
		Unsigned32( h0 ), Unsigned32( h1 ), Unsigned32( h2 ),
		Unsigned32( h3 ), Unsigned32( h4 ) )
end

local nativeSHA1 = util.SHA1
local nativeSHA1OK = isfunction( nativeSHA1 )
	and string.lower( tostring( nativeSHA1( "abc" ) ) )
		== "a9993e364706816aba3e25717850c26c9cd0d89d"

function AdvMat.SHA1( source )
	local digest = nativeSHA1OK and nativeSHA1( source ) or PureSHA1( source )
	return string.lower( tostring( digest ) )
end
