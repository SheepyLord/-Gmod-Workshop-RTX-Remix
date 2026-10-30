--[[---------------------------------------------------------------------------
	Advanced Material Editor - normal maps for RTX Remix

	Remix reads every replacement normal map as UNSIGNED OCTAHEDRAL. In the
	c6b48ed1 runtime this client runs, the opaque material decodes its normal
	sample with unsignedOctahedralToHemisphereDirection (packing.slangh) and
	nothing else:

		s = rg * 2 - 1
		t = ( s.x + s.y, s.x - s.y ) / 2
		n = normalize( t.x, t.y, 1 - |t.x| - |t.y| )

	`inputs:encoding` is not in the opaque material's parameter table
	(rtx_material_data.h), so the tangent-space encoding AME used to author
	changed nothing, and AME's own normal maps - tangent-space RGB, like every
	Source normal map - were read as octahedral: relief turned 45 degrees and
	bent, 14 to 18 degrees off on average at the generator's default strength
	and over 100 degrees on the steepest texels.

	Which way is +y: the runtime builds the tangent frame from the triangle's
	dP/du and dP/dv (genTangSpace, math.slangh), with v as the game supplies
	it, growing DOWN the picture. A DirectX-style map - green brighter where
	the surface faces the bottom of the picture, which is what Source reads
	and what AME's generator draws - therefore goes in as it is, and an
	OpenGL-style map has its green flipped. AperturePBR_Normal.mdl, which the
	Remix Toolkit renders with, decodes the two the same way.

	So the bridge converts the picture a profile names, on its way to the
	native writer, with the inverse of the runtime's decode
	(hemisphereDirectionToUnsignedOctahedral):

		q  = n.xy / ( |n.x| + |n.y| + n.z )
		rg = ( q.x + q.y, q.x - q.y ) / 2 + 1/2         rounded to bytes

	Rounding is the whole error: within 0.55 degrees of the intended normal
	everywhere, 0.2 on average (trying all four neighbouring byte pairs
	gains a thousandth of a degree, so it is not done).

	Why here, and why a PNG. The writer that ships with this client is built
	into the RTX client's binary; changing it means a new DLL. Lua cannot write
	a .dds (file.Write refuses the extension), so what it hands over is a
	picture, and the writer builds that picture's mip chain itself: each 2x2
	mean of R, G and B is RENORMALISED as a 3D vector (texture_ingest.cpp,
	EncodeDds). Right for tangent space, wrong for octahedral data - unless
	blue is chosen for it. Remix never reads blue, so it is set to
	sqrt( 1 - s.x^2 - s.y^2 ): that makes ( s, b ) a unit vector, and the
	renormalisation leaves an even area alone. Measured against the writer's
	exact arithmetic on generated normal maps (512 px, strength 4; error
	against the mean direction of the full-size normals under each texel):

		blue                      mip 1           mip 3           mip 6
		sqrt(1 - |s|^2)   mean  0.7 - 0.9 deg   1.2 deg         1.0 deg
		                  p99   5 - 8           4 - 5           1.7 - 1.9
		0 or 255          mean  1.8 - 2.3       1.7 - 2.0       1.0 - 1.1
		                  p99   15 - 17         8 - 9           1.7 - 2.2

	An ideal chain is under 0.2. What remains has two parts. Near the top of
	the chain, on rough detail, the writer averages ( s, b ) rather than the
	directions themselves. Further down it is the writer truncating every
	2x2 mean, a drift of about 0.2 degrees a level that it adds to every map
	it mips, tangent space included: with rounded means the same chains end
	at 0.5 degrees instead of 1.0. A writer that averaged the texels' decoded
	directions would leave only the rounding (see HANDOVER.md).

	What is converted (Plan):
	  * a picture named with tangent_space_dx or tangent_space_ogl: AME's
	    generator, an edit, an import, a PNG or DDS you named;
	  * the bake of a normal_from_height operation (and any invert or multiply
	    before it), done here because it has to come before the conversion
	    and the writer would only bake what it is handed;
	  * an octahedral picture keeps its red and green and gets the blue above.
	What is not: an enhancement's own DDS, which Remix already reads, and any
	octahedral DDS, which the writer copies as it is, mips included. The
	converted copy lives in data/advmat/remix/ beside the enhancement
	stand-ins and is swept with them; the profile keeps naming its own picture
	and encoding, so nothing saved or shared changes, and the vanilla editor
	never comes here.

	The same reader, queue and folder shrink other pictures too (N.Fit): a
	recipe's PNG larger than the writer decodes - Edit on a 4096 px
	enhancement map makes one - goes over as a copy halved until it fits,
	each texel the mean of the bytes under it, alpha kept. A normal map is
	never shrunk that way; its conversion halves it by averaging directions.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.RTX = AdvMat.RTX or {}
AdvMat.RTX.Normals = AdvMat.RTX.Normals or {}

local N = AdvMat.RTX.Normals

-- Part of every converted file's name. Bump it whenever the bytes written for
-- the same picture change, or old conversions would be served.
N.VERSION = 1

N.Ready  = N.Ready or {}    -- [job key] = "data/..." output
N.Failed = N.Failed or {}   -- [job key] = { at, reason }
N.Wait   = N.Wait or {}     -- [job key] = { job, callbacks }
N.Queue  = N.Queue or {}

local byte, char, sub, lower, gsub = string.byte, string.char, string.sub, string.lower, string.gsub
local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local concat = table.concat
local unpack = unpack or table.unpack

-- A 2048 px conversion is a few million pixels of Lua; it runs a few
-- milliseconds a frame, like the enhancement decoder beside it.
local FRAME_BUDGET = 0.006

local IMAGE_DIR = "advmat/remix"

local ENCODINGS = { octahedral = true, tangent_space_dx = true, tangent_space_ogl = true }

local function Clock() return ( SysTime or os.clock )() end

-- Lua 5.1 says nil on the main thread; 5.2 and later say (thread, true).
local function Yield( budget )
	local thread, main = coroutine.running()
	if thread and not main and budget and Clock() > budget.until_ then
		coroutine.yield()
	end
end

---------------------------------------------------------------------------
-- File access
---------------------------------------------------------------------------
-- Paths here are relative to the game folder. Files under garrysmod/data/ -
-- every recipe's picture and every decoded copy - are read through DATA
-- itself; anything else through BASE_PATH, the way cl_28_rtx_enhance.lua
-- reads the mods. Everything goes through this table so the tests can hand it
-- files.

local function Where( path )
	local data = string.match( path, "^[Gg][Aa][Rr][Rr][Yy][Ss][Mm][Oo][Dd]/[Dd][Aa][Tt][Aa]/(.+)$" )
	if data then return data, "DATA" end
	return path, "BASE_PATH"
end

N.FS = N.FS or {
	Read = function( path ) local where, id = Where( path ) return file.Read( where, id ) end,
	Size = function( path ) local where, id = Where( path ) return file.Size( where, id ) end,
	Time = function( path ) local where, id = Where( path ) return file.Time( where, id ) end,
}

local FS = N.FS

--- A map path as the native writer resolves a relative source - against the
--- game folder, then garrysmod/, then garrysmod/data/ - so the file read here
--- is the file the writer would have read. Returns the game-folder path and
--- its size, or nil.
function N.Resolve( path )
	if not isstring( path ) or path == "" then return nil end
	path = gsub( path, "\\", "/" )
	for _, candidate in ipairs( { path, "garrysmod/" .. path, "garrysmod/data/" .. path } ) do
		local size = tonumber( FS.Size( candidate ) ) or -1
		if size > 0 then return candidate, size end
	end
	return nil
end

---------------------------------------------------------------------------
-- The encoding
---------------------------------------------------------------------------

local function Byte( value )
	value = floor( value * 255 + 0.5 )
	if value < 0 then return 0 end
	if value > 255 then return 255 end
	return value
end

--- The octahedral bytes for the direction ( x, y, z ). Any length will do -
--- the projection divides it out - and a direction below the surface is laid
--- on it, which the hemisphere encoding cannot represent anyway.
function N.Encode( x, y, z )
	if z < 0 then z = 0 end
	local l1 = abs( x ) + abs( y ) + z
	if l1 <= 1e-12 then return 128, 128 end
	x, y = x / l1, y / l1
	return Byte( ( x + y ) * 0.5 + 0.5 ), Byte( ( x - y ) * 0.5 + 0.5 )
end

--- The unit normal the runtime reads from octahedral bytes r, g:
--- unsignedOctahedralToHemisphereDirection at the default intensity.
function N.Decode( r, g )
	local sx, sy = r / 127.5 - 1, g / 127.5 - 1
	local tx, ty = ( sx + sy ) * 0.5, ( sx - sy ) * 0.5
	local tz = 1 - abs( tx ) - abs( ty )
	local length = sqrt( tx * tx + ty * ty + tz * tz )
	return tx / length, ty / length, tz / length
end

--- The blue byte that makes the writer's mip renormalisation leave octahedral
--- bytes r, g alone: ( r, g, b ) read as the writer reads them, v / 127.5 - 1,
--- is then a unit vector. Past the inscribed circle (tilts over 67 degrees
--- along an axis) no blue can, and zero shortens the least.
function N.Blue( r, g )
	local x, y = r / 127.5 - 1, g / 127.5 - 1
	local zz = 1 - x * x - y * y
	return Byte( ( zz > 0 and sqrt( zz ) or 0 ) * 0.5 + 0.5 )
end

--- The direction a tangent-space texel means, the way AperturePBR_Normal.mdl
--- reads tangent_space_dx (and, with `flipGreen`, tangent_space_ogl):
--- normalize( rgb * 2 - 1 ). A texel whose blue points into the surface -
--- a two-channel map saved with blue at zero, or plain black - has no valid
--- z, so z is rebuilt from x and y instead of turning the texel sideways.
function N.TangentVector( r, g, b, flipGreen )
	local x, y, z = r / 127.5 - 1, g / 127.5 - 1, b / 127.5 - 1
	if flipGreen then y = -y end
	if z < 0 then
		local zz = 1 - x * x - y * y
		z = zz > 0 and sqrt( zz ) or 0
	end
	local length = sqrt( x * x + y * y + z * z )
	if length < 1e-6 then return 0, 0, 1 end
	return x / length, y / length, z / length
end

---------------------------------------------------------------------------
-- Reading PNG
---------------------------------------------------------------------------
-- Every normal map AME makes is a PNG: the generator's (fixed Huffman with
-- runs, cl_55_normalgen.lua), a decoded enhancement copy (stored blocks,
-- cl_28_rtx_enhance.lua), or a picture you named, which can come from
-- anything - so the whole of inflate is here, dynamic codes included.

local POW2 = {}
do
	local p = 1
	for i = 0, 40 do POW2[ i ] = p p = p * 2 end
end

-- Codes up to this long are decoded with one table lookup; longer ones (only
-- dynamic blocks have them) a bit at a time.
local FAST = 9
local FAST_SIZE = POW2[ FAST ]

--- Canonical Huffman decoding tables for code lengths [0 .. count - 1], or nil
--- for an over-subscribed set. An incomplete one is allowed: deflate sends one
--- for a block that uses a single distance.
local function Huffman( lengths, count )
	local counts = {}
	for bits = 0, 15 do counts[ bits ] = 0 end
	for symbol = 0, count - 1 do
		local bits = lengths[ symbol ] or 0
		counts[ bits ] = counts[ bits ] + 1
	end
	counts[ 0 ] = 0

	local left = 1
	for bits = 1, 15 do
		left = left * 2 - counts[ bits ]
		if left < 0 then return nil end
	end

	local placed, nextCode, code = {}, {}, 0
	local offset = 0
	for bits = 1, 15 do
		code = ( code + counts[ bits - 1 ] ) * 2
		nextCode[ bits ] = code
		placed[ bits ] = offset
		offset = offset + counts[ bits ]
	end

	local symbols, fast = {}, {}
	for symbol = 0, count - 1 do
		local bits = lengths[ symbol ] or 0
		if bits > 0 then
			symbols[ placed[ bits ] ] = symbol
			placed[ bits ] = placed[ bits ] + 1
			local value = nextCode[ bits ]
			nextCode[ bits ] = value + 1
			if bits <= FAST then
				-- Codes go out high bit first into a stream read low bit
				-- first, so the table is indexed by each code reversed.
				local reversed = 0
				for _ = 1, bits do
					reversed = reversed * 2 + value % 2
					value = floor( value / 2 )
				end
				for index = reversed, FAST_SIZE - 1, POW2[ bits ] do
					fast[ index ] = symbol * 16 + bits
				end
			end
		end
	end
	return { counts = counts, symbols = symbols, fast = fast }
end

-- RFC 1951, 3.2.5.
local LENGTH_BASE  = { [ 0 ] = 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LENGTH_EXTRA = { [ 0 ] = 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE    = { [ 0 ] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA   = { [ 0 ] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_ORDER   = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local FIXED_LITERALS, FIXED_DISTANCES

local function FixedTables()
	if not FIXED_LITERALS then
		local lengths = {}
		for symbol = 0, 287 do
			lengths[ symbol ] = symbol < 144 and 8 or symbol < 256 and 9 or symbol < 280 and 7 or 8
		end
		FIXED_LITERALS = Huffman( lengths, 288 )
		local distances = {}
		for symbol = 0, 29 do distances[ symbol ] = 5 end
		FIXED_DISTANCES = Huffman( distances, 30 )
	end
	return FIXED_LITERALS, FIXED_DISTANCES
end

--- Inflate the zlib stream `z`, handing every byte out to `put`. Errors on a
--- malformed stream; the job's coroutine reports that as its failure.
local function Inflate( z, put )
	if #z < 2 or ( byte( z, 1 ) * 256 + byte( z, 2 ) ) % 31 ~= 0 or byte( z, 1 ) % 16 ~= 8 then
		error( "the image data is not a zlib stream", 0 )
	end
	if floor( byte( z, 2 ) / 32 ) % 2 == 1 then error( "the image data needs a preset dictionary", 0 ) end

	local length = #z
	local pos, buf, cnt = 3, 0, 0
	local window, wpos, filled = {}, 0, 0

	local function Need( n )
		while cnt < n do
			-- Past the end reads zeros: a peek may look further than the last
			-- code reaches; Bits below refuses to consume what is not there.
			buf = buf + ( byte( z, pos ) or 0 ) * POW2[ cnt ]
			pos = pos + 1
			cnt = cnt + 8
		end
	end

	local function Bits( n )
		if n == 0 then return 0 end
		Need( n )
		local p = POW2[ n ]
		local value = buf % p
		buf = ( buf - value ) / p
		cnt = cnt - n
		if pos - floor( cnt / 8 ) > length + 1 then error( "the image data ends early", 0 ) end
		return value
	end

	local function Decode( h )
		Need( FAST )
		local entry = h.fast[ buf % FAST_SIZE ]
		if entry then
			local bits = entry % 16
			local p = POW2[ bits ]
			buf = ( buf - buf % p ) / p
			cnt = cnt - bits
			return floor( entry / 16 )
		end
		local counts, symbols = h.counts, h.symbols
		local code, first, index = 0, 0, 0
		for bits = 1, 15 do
			code = code + Bits( 1 )
			local count = counts[ bits ]
			if code - count < first then return symbols[ index + code - first ] end
			index = index + count
			first = ( first + count ) * 2
			code = code * 2
		end
		error( "the image data has an invalid Huffman code", 0 )
	end

	local function Out( value )
		window[ wpos ] = value
		wpos = wpos + 1
		if wpos == 32768 then wpos = 0 end
		if filled < 32768 then filled = filled + 1 end
		put( value )
	end

	local function Dynamic()
		local literalCount = Bits( 5 ) + 257
		local distanceCount = Bits( 5 ) + 1
		local codeCount = Bits( 4 ) + 4
		local codeLengths = {}
		for index = 1, 19 do codeLengths[ CODE_ORDER[ index ] ] = 0 end
		for index = 1, codeCount do codeLengths[ CODE_ORDER[ index ] ] = Bits( 3 ) end
		local codes = Huffman( codeLengths, 19 )
		if not codes then error( "the image data has a bad code-length code", 0 ) end

		local lengths, at, total = {}, 0, literalCount + distanceCount
		while at < total do
			local symbol = Decode( codes )
			if symbol < 16 then
				lengths[ at ] = symbol
				at = at + 1
			else
				local repeatValue, times = 0, 0
				if symbol == 16 then
					if at == 0 then error( "the image data repeats a length that is not there", 0 ) end
					repeatValue, times = lengths[ at - 1 ], 3 + Bits( 2 )
				elseif symbol == 17 then
					times = 3 + Bits( 3 )
				else
					times = 11 + Bits( 7 )
				end
				if at + times > total then error( "the image data has too many code lengths", 0 ) end
				for _ = 1, times do
					lengths[ at ] = repeatValue
					at = at + 1
				end
			end
		end
		if ( lengths[ 256 ] or 0 ) == 0 then error( "the image data has no end-of-block code", 0 ) end

		local literalLengths, distanceLengths = {}, {}
		for symbol = 0, literalCount - 1 do literalLengths[ symbol ] = lengths[ symbol ] end
		for symbol = 0, distanceCount - 1 do distanceLengths[ symbol ] = lengths[ literalCount + symbol ] end
		local literals = Huffman( literalLengths, literalCount )
		local distances = Huffman( distanceLengths, distanceCount )
		if not literals or not distances then error( "the image data has a bad Huffman table", 0 ) end
		return literals, distances
	end

	repeat
		local final = Bits( 1 )
		local kind = Bits( 2 )
		if kind == 0 then
			Bits( cnt % 8 )
			local stored = Bits( 16 )
			if stored + Bits( 16 ) ~= 65535 then error( "the image data has a corrupt stored block", 0 ) end
			-- Whole bytes still buffered come first, then straight from the string.
			while stored > 0 and cnt >= 8 do
				Out( Bits( 8 ) )
				stored = stored - 1
			end
			if pos + stored - 1 > length then error( "the image data ends early", 0 ) end
			for at = pos, pos + stored - 1 do Out( byte( z, at ) ) end
			pos = pos + stored
		elseif kind == 1 or kind == 2 then
			local literals, distances
			if kind == 1 then
				literals, distances = FixedTables()
			else
				literals, distances = Dynamic()
			end
			while true do
				local symbol = Decode( literals )
				if symbol < 256 then
					Out( symbol )
				elseif symbol == 256 then
					break
				else
					symbol = symbol - 257
					if symbol > 28 then error( "the image data has an invalid length", 0 ) end
					local count = LENGTH_BASE[ symbol ] + Bits( LENGTH_EXTRA[ symbol ] )
					local code = Decode( distances )
					if code > 29 then error( "the image data has an invalid distance", 0 ) end
					local distance = DIST_BASE[ code ] + Bits( DIST_EXTRA[ code ] )
					if distance > filled then error( "the image data reaches back too far", 0 ) end
					for _ = 1, count do
						local from = wpos - distance
						if from < 0 then from = from + 32768 end
						Out( window[ from ] )
					end
				end
			end
		else
			error( "the image data has an invalid block type", 0 )
		end
	until final == 1
end

local function U32BE( data, at )
	local a, b, c, d = byte( data, at, at + 3 )
	return ( ( a * 256 + b ) * 256 + c ) * 256 + d
end

-- Channels per pixel for each colour type, and the bit depths it may use.
local COLOUR_TYPES = {
	[ 0 ] = { channels = 1, depths = { [ 1 ] = true, [ 2 ] = true, [ 4 ] = true, [ 8 ] = true, [ 16 ] = true } },
	[ 2 ] = { channels = 3, depths = { [ 8 ] = true, [ 16 ] = true } },
	[ 3 ] = { channels = 1, depths = { [ 1 ] = true, [ 2 ] = true, [ 4 ] = true, [ 8 ] = true } },
	[ 4 ] = { channels = 2, depths = { [ 8 ] = true, [ 16 ] = true } },
	[ 6 ] = { channels = 4, depths = { [ 8 ] = true, [ 16 ] = true } },
}

local CHAR_LIMIT = 4096

local function RowString( row, first, last )
	if last - first < CHAR_LIMIT then return char( unpack( row, first, last ) ) end
	local parts = {}
	for at = first, last, CHAR_LIMIT do
		parts[ #parts + 1 ] = char( unpack( row, at, min( last, at + CHAR_LIMIT - 1 ) ) )
	end
	return concat( parts )
end

local function Paeth( a, b, c )
	local p = a + b - c
	local pa, pb, pc = abs( p - a ), abs( p - b ), abs( p - c )
	if pa <= pb and pa <= pc then return a end
	if pb <= pc then return b end
	return c
end

--- Undo a row's filter in place. `cur[ 1 ]` is the filter byte and the data
--- follows; `prev` is the row above, already unfiltered.
local function Unfilter( cur, prev, count, bpp )
	local filter = cur[ 1 ]
	if filter == 0 then return end
	if filter == 1 then
		for i = 2 + bpp, count do cur[ i ] = ( cur[ i ] + cur[ i - bpp ] ) % 256 end
	elseif filter == 2 then
		for i = 2, count do cur[ i ] = ( cur[ i ] + prev[ i ] ) % 256 end
	elseif filter == 3 then
		for i = 2, count do
			local left = i - bpp >= 2 and cur[ i - bpp ] or 0
			cur[ i ] = ( cur[ i ] + floor( ( left + prev[ i ] ) / 2 ) ) % 256
		end
	elseif filter == 4 then
		for i = 2, count do
			local left = i - bpp >= 2
			cur[ i ] = ( cur[ i ] + Paeth( left and cur[ i - bpp ] or 0, prev[ i ],
				left and prev[ i - bpp ] or 0 ) ) % 256
		end
	else
		error( "the image uses an unknown row filter (" .. tostring( filter ) .. ")", 0 )
	end
end

--- A PNG decoded to rows of RGBA bytes: { width, height, rows = { [0] = "..." } }.
--- Every colour type and bit depth PNG has is read except interlacing; 16-bit
--- samples keep their high byte. Errors with a reason on anything malformed.
--- Inside a coroutine it pauses at row ends whenever `budget.until_` passes.
function N.ReadPNG( data, budget )
	if not isstring( data ) or sub( data, 1, 8 ) ~= "\137PNG\r\n\26\n" then
		error( "not a PNG file", 0 )
	end

	local width, height, depth, colour, interlace
	local palette, transparency = nil, nil
	local idat = {}
	local at = 9
	while at + 11 <= #data do
		local size = U32BE( data, at )
		local kind = sub( data, at + 4, at + 7 )
		if at + 11 + size > #data then error( "the PNG is truncated", 0 ) end
		if kind == "IHDR" then
			width, height = U32BE( data, at + 8 ), U32BE( data, at + 12 )
			depth, colour = byte( data, at + 16 ), byte( data, at + 17 )
			interlace = byte( data, at + 20 )
		elseif kind == "PLTE" then
			palette = sub( data, at + 8, at + 7 + size )
		elseif kind == "tRNS" then
			transparency = sub( data, at + 8, at + 7 + size )
		elseif kind == "IDAT" then
			idat[ #idat + 1 ] = sub( data, at + 8, at + 7 + size )
		elseif kind == "IEND" then
			break
		end
		at = at + 12 + size
	end

	local spec = colour and COLOUR_TYPES[ colour ]
	if not width or not spec then error( "the PNG has no usable header", 0 ) end
	if width < 1 or height < 1 or width > 32768 or height > 32768 then error( "the PNG's size is invalid", 0 ) end
	if not spec.depths[ depth ] then error( "the PNG's bit depth is not valid for its colour type", 0 ) end
	if interlace ~= 0 then error( "interlaced PNGs are not read; save it without interlacing", 0 ) end
	if colour == 3 and not palette then error( "the PNG has no palette", 0 ) end
	if #idat == 0 then error( "the PNG has no image data", 0 ) end

	local channels = spec.channels
	local stride = floor( ( width * channels * depth + 7 ) / 8 )
	local bpp = max( 1, floor( channels * depth / 8 ) )
	local rowBytes = stride + 1

	-- Grey and palette samples narrower than a byte, and 16-bit samples, go
	-- through one general path; 8-bit RGB and RGBA, which is every map AME
	-- writes, are copied straight.
	local scale = depth < 8 and floor( 255 / ( POW2[ depth ] - 1 ) ) or 1
	local function Sample( row, index )
		if depth == 8 then return row[ 2 + index ] end
		if depth == 16 then return row[ 2 + index * 2 ] end
		local bitAt = index * depth
		local value = row[ 2 + floor( bitAt / 8 ) ]
		local shift = 8 - depth - bitAt % 8
		return floor( value / POW2[ shift ] ) % POW2[ depth ]
	end

	local rows, y = {}, 0
	local cur, prev, fill = {}, {}, 0
	for i = 1, rowBytes do prev[ i ] = 0 end
	local out = {}

	local function Expand( row )
		if depth == 8 and colour == 6 then return RowString( row, 2, rowBytes ) end
		local o = 1
		if depth == 8 and colour == 2 then
			local i = 2
			for _ = 1, width do
				out[ o ], out[ o + 1 ], out[ o + 2 ], out[ o + 3 ] = row[ i ], row[ i + 1 ], row[ i + 2 ], 255
				i = i + 3
				o = o + 4
			end
			return RowString( out, 1, width * 4 )
		end
		for x = 0, width - 1 do
			local r, g, b, a
			if colour == 2 then
				r, g, b, a = Sample( row, x * 3 ), Sample( row, x * 3 + 1 ), Sample( row, x * 3 + 2 ), 255
			elseif colour == 6 then
				r, g, b, a = Sample( row, x * 4 ), Sample( row, x * 4 + 1 ), Sample( row, x * 4 + 2 ), Sample( row, x * 4 + 3 )
			elseif colour == 0 then
				r = Sample( row, x ) * scale
				g, b, a = r, r, 255
			elseif colour == 4 then
				r, a = Sample( row, x * 2 ), Sample( row, x * 2 + 1 )
				g, b = r, r
			else
				local index = Sample( row, x )
				r, g, b = byte( palette, index * 3 + 1, index * 3 + 3 )
				if not b then error( "the PNG names a colour its palette does not have", 0 ) end
				a = transparency and byte( transparency, index + 1 ) or 255
			end
			out[ o ], out[ o + 1 ], out[ o + 2 ], out[ o + 3 ] = r, g, b, a
			o = o + 4
		end
		return RowString( out, 1, width * 4 )
	end

	Inflate( concat( idat ), function( value )
		if y >= height then return end
		fill = fill + 1
		cur[ fill ] = value
		if fill == rowBytes then
			Unfilter( cur, prev, rowBytes, bpp )
			rows[ y ] = Expand( cur )
			y = y + 1
			cur, prev, fill = prev, cur, 0
			Yield( budget )
		end
	end )
	if y < height then error( "the PNG's image data is short", 0 ) end

	return { width = width, height = height, rows = rows }
end

---------------------------------------------------------------------------
-- Map operations
---------------------------------------------------------------------------
-- The writer's own bake (texture_ingest.cpp, ApplyOperations) - invert,
-- multiply and normal_from_height, in order, on the picture's bytes - done
-- here because the writer bakes before it could convert. The Sobel, its
-- edge clamping, the channel weights and the strength are the writer's; the
-- normal bytes are rounded where it truncates.

local function Clamp255( value )
	if value < 0 then return 0 end
	if value > 255 then return 255 end
	return value
end

local function MapRows( image, transform, budget )
	local out = {}
	for y = 0, image.height - 1 do
		local row = image.rows[ y ]
		local o = 1
		for x = 0, image.width - 1 do
			local r, g, b, a = byte( row, x * 4 + 1, x * 4 + 4 )
			r, g, b = transform( r, g, b )
			out[ o ], out[ o + 1 ], out[ o + 2 ], out[ o + 3 ] = r, g, b, a
			o = o + 4
		end
		image.rows[ y ] = RowString( out, 1, image.width * 4 )
		Yield( budget )
	end
end

local HEIGHT_CHANNELS = { r = 1, g = 2, b = 3, a = 4 }

local function NormalFromHeight( image, strength, channel, budget )
	local w, h = image.width, image.height
	local source = image.rows
	local which = HEIGHT_CHANNELS[ channel ]
	-- One row of heights at a time, built once per source row.
	local heights = {}
	local function Heights( y )
		if y < 0 then y = 0 elseif y > h - 1 then y = h - 1 end
		local cached = heights[ y ]
		if cached then return cached end
		local row, line = source[ y ], {}
		for x = 0, w - 1 do
			local r, g, b, a = byte( row, x * 4 + 1, x * 4 + 4 )
			if which == 1 then line[ x ] = r / 255
			elseif which == 2 then line[ x ] = g / 255
			elseif which == 3 then line[ x ] = b / 255
			elseif which == 4 then line[ x ] = a / 255
			else line[ x ] = ( r * 0.2126 + g * 0.7152 + b * 0.0722 ) / 255 end
		end
		heights[ y ] = line
		return line
	end

	local rows, out = {}, {}
	for y = 0, h - 1 do
		local above, here, below = Heights( y - 1 ), Heights( y ), Heights( y + 1 )
		heights[ y - 2 ] = nil
		local o = 1
		for x = 0, w - 1 do
			local left, right = x > 0 and x - 1 or 0, x < w - 1 and x + 1 or w - 1
			local gx = -above[ left ] - 2 * here[ left ] - below[ left ]
				+ above[ right ] + 2 * here[ right ] + below[ right ]
			local gy = -above[ left ] - 2 * above[ x ] - above[ right ]
				+ below[ left ] + 2 * below[ x ] + below[ right ]
			local nx, ny = -gx * strength, -gy * strength
			local length = sqrt( nx * nx + ny * ny + 1 )
			out[ o ] = Byte( ( nx / length ) * 0.5 + 0.5 )
			out[ o + 1 ] = Byte( ( ny / length ) * 0.5 + 0.5 )
			out[ o + 2 ] = Byte( ( 1 / length ) * 0.5 + 0.5 )
			out[ o + 3 ] = 255
			o = o + 4
		end
		rows[ y ] = RowString( out, 1, w * 4 )
		Yield( budget )
	end
	image.rows = rows
end

--- Apply a map's operations to `image` in order, as the writer would have.
function N.ApplyOps( image, ops, budget )
	for _, op in ipairs( ops or {} ) do
		local kind = op.op
		if kind == "invert" then
			MapRows( image, function( r, g, b ) return 255 - r, 255 - g, 255 - b end, budget )
		elseif kind == "multiply" then
			local fr, fg, fb
			if istable( op.color ) then
				fr = tonumber( op.color.r or op.color.x or op.color[ 1 ] ) or 1
				fg = tonumber( op.color.g or op.color.y or op.color[ 2 ] ) or 1
				fb = tonumber( op.color.b or op.color.z or op.color[ 3 ] ) or 1
			else
				fr = tonumber( op.value ) or 1
				fg, fb = fr, fr
			end
			MapRows( image, function( r, g, b )
				return floor( Clamp255( r * fr ) ), floor( Clamp255( g * fg ) ), floor( Clamp255( b * fb ) )
			end, budget )
		elseif kind == "normal_from_height" then
			NormalFromHeight( image, tonumber( op.strength ) or 1, op.channel, budget )
		else
			error( "unsupported map operation " .. tostring( kind ), 0 )
		end
	end
end

---------------------------------------------------------------------------
-- Converting
---------------------------------------------------------------------------

--- How many halvings bring width x height inside the writer's limits: no side
--- over maxTextureDimension, and a BGRA mip chain - 4 bytes a pixel plus a
--- third - inside maxTextureBytes, as cl_28_rtx_enhance.lua's PickLevel counts.
function N.Halvings( width, height, limits )
	local maxDimension = limits and tonumber( limits.maxTextureDimension ) or 2048
	local maxBytes = limits and tonumber( limits.maxTextureBytes ) or 33554432
	local halvings = 0
	while ( width > maxDimension or height > maxDimension or width * height * 16 / 3 > maxBytes )
		and ( width > 1 or height > 1 ) do
		width, height = max( 1, floor( width / 2 ) ), max( 1, floor( height / 2 ) )
		halvings = halvings + 1
	end
	return halvings, width, height
end

--- The octahedral picture for `image`, whose texels are `input`
--- ("octahedral", "tangent_space_dx" or "tangent_space_ogl"), as RGB PNG
--- bytes, its width and height. A picture larger than `limits` allow is
--- reduced by whole halvings, averaging the texels' directions - never their
--- bytes, which for octahedral data would not be a direction at all.
function N.Convert( image, input, limits, budget )
	local enhance = AdvMat.RTX.Enhance
	if not enhance or not isfunction( enhance.NewPNG ) then error( "the PNG writer is unavailable", 0 ) end
	local octahedral = input == "octahedral"
	local flip = input == "tangent_space_ogl"
	local halvings, outW, outH = N.Halvings( image.width, image.height, limits )
	local png = enhance.NewPNG( outW, outH, 2 )
	local out = {}
	local Encode, Blue, TangentVector, Decode = N.Encode, N.Blue, N.TangentVector, N.Decode

	if halvings == 0 then
		for y = 0, outH - 1 do
			local row = image.rows[ y ]
			local o = 1
			for x = 0, outW - 1 do
				local r, g, b = byte( row, x * 4 + 1, x * 4 + 3 )
				if not octahedral then r, g = Encode( TangentVector( r, g, b, flip ) ) end
				out[ o ], out[ o + 1 ], out[ o + 2 ] = r, g, Blue( r, g )
				o = o + 3
			end
			png:Row( RowString( out, 1, outW * 3 ) )
			image.rows[ y ] = nil
			Yield( budget )
		end
		return png:Finish(), outW, outH
	end

	local side = POW2[ halvings ]
	local sx, sy, sz = {}, {}, {}
	for y = 0, outH - 1 do
		for x = 0, outW - 1 do sx[ x ], sy[ x ], sz[ x ] = 0, 0, 0 end
		for line = y * side, y * side + side - 1 do
			local row = image.rows[ line ]
			for x = 0, outW - 1 do
				local ax, ay, az = sx[ x ], sy[ x ], sz[ x ]
				for column = x * side, x * side + side - 1 do
					local r, g, b = byte( row, column * 4 + 1, column * 4 + 3 )
					local nx, ny, nz
					if octahedral then
						nx, ny, nz = Decode( r, g )
					else
						nx, ny, nz = TangentVector( r, g, b, flip )
					end
					ax, ay, az = ax + nx, ay + ny, az + nz
				end
				sx[ x ], sy[ x ], sz[ x ] = ax, ay, az
			end
			image.rows[ line ] = nil
			Yield( budget )
		end
		local o = 1
		for x = 0, outW - 1 do
			local r, g = Encode( sx[ x ], sy[ x ], sz[ x ] )
			out[ o ], out[ o + 1 ], out[ o + 2 ] = r, g, Blue( r, g )
			o = o + 3
		end
		png:Row( RowString( out, 1, outW * 3 ) )
	end
	return png:Finish(), outW, outH
end

--- `image` halved until it fits `limits`, as RGBA PNG bytes, its width and
--- height: each texel the mean of the bytes under it, alpha included. For a
--- picture that is not a normal map (N.Fit).
function N.Shrink( image, limits, budget )
	local enhance = AdvMat.RTX.Enhance
	if not enhance or not isfunction( enhance.NewPNG ) then error( "the PNG writer is unavailable", 0 ) end
	local halvings, outW, outH = N.Halvings( image.width, image.height, limits )
	local png = enhance.NewPNG( outW, outH, 6 )
	local side = POW2[ halvings ]
	local area = side * side
	local out, sr, sg, sb, sa = {}, {}, {}, {}, {}
	for y = 0, outH - 1 do
		for x = 0, outW - 1 do sr[ x ], sg[ x ], sb[ x ], sa[ x ] = 0, 0, 0, 0 end
		for line = y * side, y * side + side - 1 do
			local row = image.rows[ line ]
			for x = 0, outW - 1 do
				local r, g, b, a = sr[ x ], sg[ x ], sb[ x ], sa[ x ]
				for column = x * side, x * side + side - 1 do
					local cr, cg, cb, ca = byte( row, column * 4 + 1, column * 4 + 4 )
					r, g, b, a = r + cr, g + cg, b + cb, a + ca
				end
				sr[ x ], sg[ x ], sb[ x ], sa[ x ] = r, g, b, a
			end
			image.rows[ line ] = nil
			Yield( budget )
		end
		local o = 1
		for x = 0, outW - 1 do
			out[ o ], out[ o + 1 ] = floor( sr[ x ] / area + 0.5 ), floor( sg[ x ] / area + 0.5 )
			out[ o + 2 ], out[ o + 3 ] = floor( sb[ x ] / area + 0.5 ), floor( sa[ x ] / area + 0.5 )
			o = o + 4
		end
		png:Row( RowString( out, 1, outW * 4 ) )
	end
	return png:Finish(), outW, outH
end

---------------------------------------------------------------------------
-- What the writer gets
---------------------------------------------------------------------------

local function Extension( path )
	return lower( string.match( path or "", "%.([%w]+)$" ) or "" )
end

local function IsEnhancement( path )
	local enhance = AdvMat.RTX.Enhance
	return enhance and isfunction( enhance.IsModTexture ) and enhance.IsModTexture( path ) or false
end

--- What the bridge must do with a compiled profile's normal map `map` when
--- the profile says `encoding`: nil when the map goes to the writer as it is;
--- a job for N.Request; or nil plus a reason when it cannot be converted.
---
--- A normal_from_height bake is drawn here in DirectX tangent space whatever
--- the profile says: the encoding describes the picture the profile names,
--- and for a bake that is a height map.
function N.Plan( map, encoding )
	local source = isstring( map ) and map or ( istable( map ) and map.source ) or nil
	if not isstring( source ) or source == "" then return nil end
	local file = istable( map ) and isstring( map.generatedFile ) and map.generatedFile or source
	local ops = istable( map ) and istable( map.ops ) and map.ops or {}
	local bake = false
	for _, op in ipairs( ops ) do
		if istable( op ) and op.op == "normal_from_height" then bake = true end
	end
	local input = bake and "tangent_space_dx"
		or ( ENCODINGS[ encoding ] and encoding or "tangent_space_dx" )

	-- An enhancement's own map is what Remix draws today: never converted. A
	-- decoded copy of one (too big for the writer, or linked in) is a picture
	-- the writer will mip, so an octahedral one gets its blue.
	if not bake and IsEnhancement( source ) and not ( istable( map ) and map.recipe ) then
		if input ~= "octahedral" or file == source then return nil end
		return { file = file, input = input, ops = ops }
	end

	local extension = Extension( file )
	if extension == "dds" then
		-- The writer copies a DDS as it is, mip chain and all.
		if input == "octahedral" and #ops == 0 then return nil end
		return { file = file, input = input, ops = ops, dds = true }
	end
	if extension ~= "png" then
		if input == "octahedral" and #ops == 0 then return nil end
		return nil, "Remix reads only octahedral normal maps and AME converts PNG and DDS files, not ."
			.. extension .. " - open it with Edit, which keeps a PNG, or save it as PNG"
	end
	return { file = file, input = input, ops = ops }
end

local function OpsKey( ops )
	local parts = {}
	for _, op in ipairs( ops or {} ) do
		local color = istable( op.color ) and op.color or nil
		parts[ #parts + 1 ] = string.format( "%s:%.9g:%.9g:%.9g:%.9g:%.9g:%s", tostring( op.op ),
			tonumber( op.value ) or -1,
			color and tonumber( color.r or color.x or color[ 1 ] ) or -1,
			color and tonumber( color.g or color.y or color[ 2 ] ) or -1,
			color and tonumber( color.b or color.z or color[ 3 ] ) or -1,
			tonumber( op.strength ) or -1, tostring( op.channel or "" ) )
	end
	return concat( parts, ";" )
end

local function EnsureFolder()
	if not file.IsDir( "advmat", "DATA" ) then file.CreateDir( "advmat" ) end
	if not file.IsDir( IMAGE_DIR, "DATA" ) then file.CreateDir( IMAGE_DIR ) end
end

local function Run( job, budget )
	local data = FS.Read( job.path )
	if not isstring( data ) then return nil, "could not read " .. job.path end
	local image = N.ReadPNG( data, budget )
	data = nil
	job.from = image.width .. "x" .. image.height
	if #job.ops > 0 then N.ApplyOps( image, job.ops, budget ) end
	local png, width, height
	if job.fit then
		png, width, height = N.Shrink( image, job.limits, budget )
	else
		png, width, height = N.Convert( image, job.input, job.limits, budget )
	end
	job.to = width .. "x" .. height

	EnsureFolder()
	file.Write( job.output, png )
	if file.Read( job.output, "DATA" ) ~= png then
		pcall( file.Delete, job.output )
		return nil, "could not write data/" .. job.output
	end
	return "data/" .. job.output
end

-- The last few conversions, for advmat_rtx_normals.
N.Recent = N.Recent or {}

local function Finish( job, output, reason, frames, seconds )
	local waiting = N.Wait[ job.key ]
	N.Wait[ job.key ] = nil
	if output then
		N.Ready[ job.key ] = output
		N.Failed[ job.key ] = nil
	else
		N.Failed[ job.key ] = { at = Clock(), reason = reason }
		AdvMat.Log( job.fit and "Could not shrink %s for the RTX writer: %s"
			or "Could not convert the normal map %s: %s", job.path, tostring( reason ) )
	end
	table.insert( N.Recent, 1, {
		path = job.path, input = job.input, ops = #job.ops, output = output, reason = reason,
		from = job.from, to = job.to, frames = frames or 0, seconds = seconds or 0,
	} )
	N.Recent[ 9 ] = nil
	for _, done in ipairs( waiting and waiting.callbacks or {} ) do
		local ok, err = pcall( done, output, reason )
		if not ok then AdvMat.Log( "RTX normal map callback failed: %s", tostring( err ) ) end
	end
end

local worker

-- One job at a time, resumed once a frame, exactly like the enhancement
-- decoder's queue.
local function Pump()
	if not worker then
		local job = table.remove( N.Queue, 1 )
		if not job then
			hook.Remove( "Think", "AdvMat.RTXNormals" )
			return
		end
		worker = { job = job, thread = coroutine.create( Run ), budget = {}, started = false,
			frames = 0, since = Clock() }
	end

	worker.budget.until_ = Clock() + FRAME_BUDGET
	worker.frames = worker.frames + 1
	local ok, output, reason
	if worker.started then
		ok, output, reason = coroutine.resume( worker.thread )
	else
		worker.started = true
		ok, output, reason = coroutine.resume( worker.thread, worker.job, worker.budget )
	end
	if ok and coroutine.status( worker.thread ) ~= "dead" then return end

	local done = worker
	worker = nil
	if not ok then output, reason = nil, tostring( output ) end
	Finish( done.job, output, reason, done.frames, Clock() - done.since )
end

N.Pump = Pump

local function Queue( job, done )
	local ready = N.Ready[ job.key ]
	if ready and file.Exists( sub( ready, 6 ), "DATA" ) then
		if done then done( ready ) end
		return ready
	end
	N.Ready[ job.key ] = nil
	if file.Exists( job.output, "DATA" ) then
		N.Ready[ job.key ] = "data/" .. job.output
		if done then done( "data/" .. job.output ) end
		return "data/" .. job.output
	end

	local failed = N.Failed[ job.key ]
	if failed and Clock() - failed.at < 10 then
		if done then done( nil, failed.reason ) end
		return nil, failed.reason
	end

	local waiting = N.Wait[ job.key ]
	if waiting then
		if done then waiting.callbacks[ #waiting.callbacks + 1 ] = done end
		return nil
	end
	N.Wait[ job.key ] = { job = job, callbacks = { done } }
	N.Queue[ #N.Queue + 1 ] = job
	hook.Add( "Think", "AdvMat.RTXNormals", Pump )
	return nil
end

-- The copy is a picture, which the writer decodes and mips: a writer that
-- copies a DDS at larger sizes still decodes only up to maxDecodedTexture*.
local function PictureLimits( limits )
	limits = limits or {}
	return {
		maxTextureDimension = tonumber( limits.maxDecodedTextureDimension or limits.maxTextureDimension ) or 2048,
		maxTextureBytes = tonumber( limits.maxDecodedTextureBytes or limits.maxTextureBytes ) or 33554432,
	}
end

--- Convert a job from N.Plan for a writer with `limits` (Bridge.NativeLimits).
--- Returns the "data/advmat/remix/octn_....png" path at once when that
--- conversion already exists; otherwise queues the work, returns nil, and
--- calls `done( path | nil, reason )` when it lands.
function N.Request( plan, limits, done )
	local function Fail( reason )
		if done then done( nil, reason ) end
		return nil, reason
	end

	local picture = PictureLimits( limits )
	local maxDimension, maxBytes = picture.maxTextureDimension, picture.maxTextureBytes

	local path, size = N.Resolve( plan.file )
	if not path then return Fail( "the file does not exist" ) end

	if plan.dds then
		-- A tangent-space DDS of your own: the enhancement decoder makes a
		-- picture of its largest level that fits, and that is converted.
		local enhance = AdvMat.RTX.Enhance
		if not enhance or not isfunction( enhance.RequestImage ) then
			return Fail( "the DDS decoder is unavailable" )
		end
		local result, reason, finished = nil, nil, false
		enhance.RequestImage( path, "carry", "normal", picture, function( decoded, why )
			if finished then return end
			finished = true
			if decoded then
				result, reason = N.Request( { file = decoded, input = plan.input, ops = plan.ops }, picture, done )
			else
				result, reason = Fail( why )
			end
		end )
		if finished then return result, reason end
		return nil
	end

	local key = concat( {
		N.VERSION, lower( path ), size, tostring( FS.Time( path ) or 0 ), plan.input, OpsKey( plan.ops ),
		maxDimension, maxBytes,
	}, "|" )
	local digest = sub( AdvMat.SHA1( key ), 1, 20 )
	return Queue( {
		key = key, path = path, input = plan.input, ops = plan.ops or {}, limits = picture,
		output = IMAGE_DIR .. "/octn_" .. digest .. ".png",
	}, done )
end

--- A PNG that is not a normal map, halved until a writer with `limits` decodes
--- it: "data/advmat/remix/fit_....png", returned or queued like N.Request.
function N.Fit( file, limits, done )
	local function Fail( reason )
		if done then done( nil, reason ) end
		return nil, reason
	end

	local picture = PictureLimits( limits )
	local path, size = N.Resolve( file )
	if not path then return Fail( "the file does not exist" ) end
	if Extension( path ) ~= "png" then return Fail( "only a PNG is shrunk for the writer" ) end

	local key = concat( {
		N.VERSION, "fit", lower( path ), size, tostring( FS.Time( path ) or 0 ),
		picture.maxTextureDimension, picture.maxTextureBytes,
	}, "|" )
	local digest = sub( AdvMat.SHA1( key ), 1, 20 )
	return Queue( {
		key = key, path = path, input = "fit", fit = true, ops = {}, limits = picture,
		output = IMAGE_DIR .. "/fit_" .. digest .. ".png",
	}, done )
end

---------------------------------------------------------------------------
-- Console report
---------------------------------------------------------------------------
-- advmat_rtx_normals   the last conversions this session, and what is queued

if CLIENT then
	concommand.Add( "advmat_rtx_normals", function()
		AdvMat.Log( "%d picture(s) waiting to be converted or shrunk for RTX Remix.", #N.Queue )
		if #N.Recent == 0 then AdvMat.Log( "  none converted this session" ) end
		for _, entry in ipairs( N.Recent ) do
			if entry.output then
				AdvMat.Log( "  %s  %s%s  %s -> %s  %s, %d frame(s), %.2f s", entry.path, entry.input,
					entry.ops > 0 and " (baked)" or "", entry.from or "?", entry.to or "?", entry.output,
					entry.frames, entry.seconds )
			else
				AdvMat.Log( "  %s  %s  failed: %s", entry.path, entry.input, tostring( entry.reason ) )
			end
		end
	end )
end
