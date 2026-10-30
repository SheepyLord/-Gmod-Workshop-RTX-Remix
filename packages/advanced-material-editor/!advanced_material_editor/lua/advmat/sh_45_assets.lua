--[[---------------------------------------------------------------------------
	Advanced Material Editor - portable generated edit assets

	A generated edit normally travels as a recipe.  Newer renderers can rebuild
	it exactly, but older clients cannot export a large edit without silently
	downscaling it.  The author therefore also publishes the verified final PNG
	through the server.  The recipe remains authoritative/editable; this module
	only transports its deterministic cached output.
-----------------------------------------------------------------------------]]

AdvMat        = AdvMat or {}
AdvMat.Assets = AdvMat.Assets or {}

local A   = AdvMat.Assets
local GEN = AdvMat.Gen

A.CHUNK_SIZE       = 30000
A.HARD_MAX_BYTES   = 64 * 1024 * 1024
A.DEFAULT_MAX_BYTES = 32 * 1024 * 1024
A.BUFFER_TTL       = 120
A.MAX_META_BYTES   = 60000

CreateConVar( "advmat_max_asset_bytes", tostring( A.DEFAULT_MAX_BYTES ),
	{ FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Largest generated edit PNG accepted from a material editor client." )

if SERVER then
	for _, name in ipairs( {
		"AdvMat.AssetBegin", "AdvMat.AssetChunk",
		"AdvMat.AssetRequest", "AdvMat.AssetAck",
		"AdvMat.AssetReject", "AdvMat.AssetMiss", "AdvMat.AssetBusy",
	} ) do
		util.AddNetworkString( name )
	end
end

function A.MaxBytes()
	local cv = GetConVar and GetConVar( "advmat_max_asset_bytes" )
	local value = cv and cv.GetInt and cv:GetInt() or A.DEFAULT_MAX_BYTES
	return math.Clamp( math.floor( tonumber( value ) or A.DEFAULT_MAX_BYTES ),
		1024, A.HARD_MAX_BYTES )
end

local function U32At( data, at )
	local a, b, c, d = string.byte( data, at, at + 3 )
	if not d then return nil end
	return ( ( ( a * 256 + b ) * 256 + c ) * 256 + d )
end

function A.Digest( data )
	if not isstring( data ) then return nil end
	-- Use one digest available on every supported GMod branch. Negotiating the
	-- "strongest" util hash made otherwise compatible old/new clients disagree
	-- about the same bytes. PNG chunk CRCs are validated independently too.
	return "crc:" .. tostring( util.CRC( data ) ) .. ":" .. tostring( #data )
end

function A.ValidTarget( target )
	return isstring( target ) and #target <= 160
		and string.match( target, "^advmat/edits/tex_[%w_%-]+%.png$" ) ~= nil
end

function A.CleanRecipe( recipe )
	if not GEN or not isfunction( GEN.Sanitize ) or not isfunction( GEN.FileName ) then
		return nil, "generated-texture schema is unavailable"
	end
	local clean = GEN.Sanitize( recipe )
	local kind
	if clean then _, kind = GEN.KindOf( clean ) end
	if not clean or kind ~= "edit" or clean._preview == true then
		return nil, "only full edited textures can be transferred"
	end
	local target = GEN.FileName( clean )
	if not A.ValidTarget( target ) then
		return nil, "generated edit path is unsafe"
	end
	local w, h = GEN.Dims( clean )
	return clean, target, w, h
end

--- Validate the PNG container without decoding untrusted image data.  The
--- engine still performs the actual image decode, so require a conventional
--- 8-bit RGB/RGBA non-interlaced file and a complete bounded chunk walk.
function A.ValidatePNG( recipe, png, expectedDigest )
	local clean, target, expectedW, expectedH = A.CleanRecipe( recipe )
	if not clean then return nil, target end
	if not isstring( png ) or #png < 45 or #png > A.MaxBytes() then
		return nil, "generated edit PNG has an invalid size"
	end
	if string.sub( png, 1, 8 ) ~= "\137PNG\13\10\26\10" then
		return nil, "generated edit is not a PNG"
	end

	local pos, chunks, sawIHDR, sawIDAT = 9, 0, false, false
	while pos <= #png do
		chunks = chunks + 1
		if chunks > 4096 or pos + 11 > #png then
			return nil, "generated edit PNG has a malformed chunk table"
		end
		local length = U32At( png, pos )
		local kind = string.sub( png, pos + 4, pos + 7 )
		if not length or length > A.MaxBytes() then
			return nil, "generated edit PNG contains an oversized chunk"
		end
		local nextPos = pos + 12 + length
		if nextPos - 1 > #png then return nil, "generated edit PNG is truncated" end
		local payload = string.sub( png, pos + 8, pos + 7 + length )
		local storedCRC = U32At( png, pos + 8 + length )
		local calculatedCRC = tonumber( util.CRC( kind .. payload ) )
		if calculatedCRC and calculatedCRC < 0 then calculatedCRC = calculatedCRC + 4294967296 end
		if not calculatedCRC or calculatedCRC % 4294967296 ~= storedCRC then
			return nil, "generated edit PNG contains a corrupt chunk"
		end

		if not sawIHDR then
			if kind ~= "IHDR" or length ~= 13 then
				return nil, "generated edit PNG does not begin with IHDR"
			end
			local w, h = U32At( png, pos + 8 ), U32At( png, pos + 12 )
			local depth, colour, compression, filter, interlace =
				string.byte( png, pos + 16, pos + 20 )
			if w ~= expectedW or h ~= expectedH then
				return nil, string.format( "generated edit PNG is %dx%d instead of %dx%d",
					w or -1, h or -1, expectedW, expectedH )
			end
			if depth ~= 8 or ( colour ~= 2 and colour ~= 6 )
				or compression ~= 0 or filter ~= 0 or interlace ~= 0 then
				return nil, "generated edit PNG uses an unsupported format"
			end
			sawIHDR = true
		elseif kind == "IHDR" then
			return nil, "generated edit PNG contains more than one IHDR"
		elseif kind == "IDAT" then
			sawIDAT = true
		elseif kind == "IEND" then
			if length ~= 0 or not sawIDAT or nextPos ~= #png + 1 then
				return nil, "generated edit PNG has an invalid IEND"
			end
			local digest = A.Digest( png )
			if expectedDigest and digest ~= expectedDigest then
				return nil, "generated edit PNG digest does not match"
			end
			return {
				recipe = clean, target = target, size = #png, digest = digest,
				width = expectedW, height = expectedH,
			}
		end
		pos = nextPos
	end

	return nil, "generated edit PNG has no IEND"
end

function A.MakeMeta( recipe, png )
	local info, reason = A.ValidatePNG( recipe, png )
	if not info then return nil, reason end
	return {
		recipe = info.recipe,
		target = info.target,
		size = info.size,
		digest = info.digest,
	}
end

function A.ValidateMeta( meta )
	if not istable( meta ) then return nil, "missing generated edit metadata" end
	local clean, target = A.CleanRecipe( meta.recipe )
	if not clean then return nil, target end
	if meta.target ~= target then return nil, "generated edit target does not match its recipe" end
	local size = math.floor( tonumber( meta.size ) or 0 )
	if size < 45 or size > A.MaxBytes() then return nil, "generated edit is too large" end
	if not isstring( meta.digest ) or #meta.digest < 8 or #meta.digest > 160
		or string.find( meta.digest, "[^%w:]" ) then
		return nil, "generated edit digest is invalid"
	end
	return { recipe = clean, target = target, size = size, digest = meta.digest }
end

function A.WireTableSafe( value, limit, label )
	local json = util.TableToJSON( value or {} )
	local packed = isstring( json ) and util.Compress( json ) or nil
	if not isstring( packed ) or #packed > ( tonumber( limit ) or A.MAX_META_BYTES ) then
		return false, tostring( label or "generated edit metadata" )
			.. " exceeds the net-message limit"
	end
	return true
end

function A.MetaWireSafe( meta )
	return A.WireTableSafe( meta, A.MAX_META_BYTES, "generated edit metadata" )
end

local function CollectEdits( value, out, seen, depth )
	if not istable( value ) or seen[ value ] or depth > 16 then return end
	seen[ value ] = true
	if value.kind == "edit" then
		local clean, target = A.CleanRecipe( value )
		if clean and not out[ target ] then out[ target ] = clean end
		return
	end
	for _, child in pairs( value ) do
		if istable( child ) then CollectEdits( child, out, seen, depth + 1 ) end
	end
end

function A.EditRecipes( value )
	local out = {}
	CollectEdits( value, out, {}, 0 )
	return out
end

--- Server commit gate: a newly published rule/profile must not promise an
--- exact multiplayer edit which the server does not actually hold.
function AdvMat.Assets.StoredEditsReady( value )
	for target, recipe in pairs( A.EditRecipes( value ) ) do
		local png = file.Read( target, "DATA" )
		if not png then return false, "server has no cached PNG for " .. target end
		local info, reason = A.ValidatePNG( recipe, png )
		if not info then return false, reason end
	end
	return true
end
