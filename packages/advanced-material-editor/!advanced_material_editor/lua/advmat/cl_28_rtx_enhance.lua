--[[---------------------------------------------------------------------------
	Advanced Material Editor - reading RTX Remix enhancement mods

	An enhancement is any Remix mod under rtx-remix/mods that replaces a
	captured material: `over "mat_<HASH>"` prims under /RootNode/Looks, whose
	Shader child carries AperturePBR inputs. Remix Toolkit projects, rpai's
	ai_pbr, map remasters and the astra importer all write them.

	How the runtime chooses (checked in the c6b48ed1 source, which is what
	this game runs):

	  * Mods are kept in a set ordered by their folder path, compared byte by
	    byte - "!advanced_material_editor" < "Emissives" < "ai_pbr" <
	    "~gmod_topbr" - and the first mod holding a material for a hash
	    supplies ALL of it. Nothing is merged across mods.
	  * Inside one mod, ordinary USD layering applies: the root layer and its
	    sublayers are composed attribute by attribute, stronger layers first,
	    and references are weaker than every local opinion.
	  * An input a material does not author falls back to the runtime's own
	    default, except the albedo texture and the sampler state, which come
	    from the game's draw call.

	AME's own mod sorts first, so an AME profile used to REPLACE an
	enhancement outright: open a character rpai had enhanced, move one slider,
	Save, and the upscaled albedo, normal, roughness and metallic maps were
	gone. This file reads the enhancement Remix is actually drawing so the
	editor can start from it, and so a saved AME profile carries every map and
	value it did not change.

	Reading needs nothing special: Garry's Mod's own BASE_PATH search path
	reaches rtx-remix/ (measured in game, including mod folders that are links
	to other drives). USDA is plain text and is parsed here; the binary USDC
	form is reported, not guessed at.

	Textures are DDS files the engine cannot load, so they are decoded here,
	one mip level at a time, into PNGs under data/advmat/remix/:

	  thumb   a small mip for the map rows' previews;
	  edit    a mip at this client's texture size, stored as an import so the
	          texture editor and the asset transport treat it like any other
	          picture from this computer (cl_61_import.lua);
	  carry   the largest mip the installed native writer will take. The bridge
	          that ships with this client refuses textures over 2048 px or
	          32 MiB and anything whose real path leaves the game folder (a mod
	          linked in from elsewhere). A map it can take is handed over
	          untouched; one it cannot goes in as this stand-in.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.RTX = AdvMat.RTX or {}
AdvMat.RTX.Enhance = AdvMat.RTX.Enhance or {}

local E = AdvMat.RTX.Enhance

E.MODS_DIR  = "rtx-remix/mods"
E.OWN_MOD   = "!advanced_material_editor"
E.TOPBR_MOD = "~gmod_topbr"

E.ModCache    = E.ModCache or {}     -- [folder] = mod record
E.LayerCache  = E.LayerCache or {}   -- [path] = { stamp, layer, err }
E.DDSCache    = E.DDSCache or {}     -- [path] = { stamp, info, err }
E.LinkedMods  = E.LinkedMods or {}   -- [folder] = the writer refused it as outside the game
E.ImageReady  = E.ImageReady or {}   -- [job key] = output path
E.ImageFailed = E.ImageFailed or {}  -- [job key] = { at, reason }
E.ImageWait   = E.ImageWait or {}    -- [job key] = { job, callbacks }
E.ImageQueue  = E.ImageQueue or {}
E.Thumbs      = E.Thumbs or {}       -- [job key] = IMaterial or false
E.Generation  = tonumber( E.Generation ) or 0
E.Mods        = E.Mods or {}

local byte, sub, find, match, gsub = string.byte, string.sub, string.find, string.match, string.gsub
local floor, min, max = math.floor, math.min, math.max
local concat = table.concat
local unpack = unpack or table.unpack

-- One layer this large is something other than a material layer (a mesh
-- capture, a scene). The two largest material layers here are about 2 MB.
local MAX_LAYER_BYTES = 24 * 1024 * 1024
local MAX_STACK       = 512
local MAX_REF_DEPTH   = 8

-- How often a lookup may stat every mod again. Remix itself only notices a
-- mod when its mod.usda changes; an editor opening a row should not re-read
-- two megabytes of USDA every time it asks.
local REFRESH_SECONDS = 2

local THUMB_SIDE = 128

-- Decoding runs a few milliseconds a frame. A 2048 px BC7 map is a quarter of
-- a million blocks of pure Lua arithmetic.
local FRAME_BUDGET = 0.006

local IMAGE_DIR = "advmat/remix"

-- Cached images that nothing asked for in this long are deleted the next time
-- the folder is touched. Every one of them can be rebuilt from its DDS.
local CACHE_DAYS = 30

---------------------------------------------------------------------------
-- File access
---------------------------------------------------------------------------
-- Everything goes through this table so the tests can hand it real files.

E.FS = E.FS or {
	Read   = function( path ) return file.Read( path, "BASE_PATH" ) end,
	Exists = function( path ) return file.Exists( path, "BASE_PATH" ) end,
	Time   = function( path ) return file.Time( path, "BASE_PATH" ) end,
	Size   = function( path ) return file.Size( path, "BASE_PATH" ) end,
	Find   = function( pattern ) return file.Find( pattern, "BASE_PATH" ) end,
	-- Bytes [offset, offset + length) of a file, or nil.
	ReadRange = function( path, offset, length )
		local handle = file.Open( path, "rb", "BASE_PATH" )
		if not handle then return nil end
		handle:Seek( offset )
		local data = handle:Read( length )
		handle:Close()
		return data
	end,
}

local FS = E.FS

local function Clock() return ( SysTime or os.clock )() end

local function Stamp( path )
	local size = tonumber( FS.Size( path ) ) or -1
	if size < 0 then return nil end
	return size .. ":" .. tostring( FS.Time( path ) or 0 ), size
end

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------
-- Every path here is relative to the game folder, with forward slashes, which
-- is what BASE_PATH takes and what the native writer resolves.

local function DirOf( path )
	return match( path, "^(.*)/[^/]*$" ) or ""
end

local function BaseName( path )
	return match( path, "([^/]*)$" ) or path
end

-- The game folder as an absolute path, when the native writer has said where
-- its own mod lives. Only used to read an absolute asset path back into the
-- game folder; most mods never write one.
local function GameRoot()
	local bridge = rawget( _G, "AdvMatRTXBridge" )
	if not istable( bridge ) or not isfunction( bridge.Capabilities ) then return nil end
	local ok, caps = pcall( bridge.Capabilities )
	local mod = ok and istable( caps ) and caps.modDirectory or nil
	if not isstring( mod ) then return nil end
	mod = gsub( mod, "\\", "/" )
	return match( mod, "^(.-)/rtx%-remix/mods/[^/]+/?$" )
end

--- `relative` read against the folder `dir`, or nil when it cannot be named
--- inside the game folder.
function E.JoinPath( dir, relative )
	if not isstring( relative ) or relative == "" then return nil end
	relative = gsub( relative, "\\", "/" )

	if find( relative, "^%a:" ) or sub( relative, 1, 1 ) == "/" then
		local root = GameRoot()
		if not root then return nil end
		local lowerRoot, lowerPath = string.lower( root ) .. "/", string.lower( relative )
		if sub( lowerPath, 1, #lowerRoot ) ~= lowerRoot then return nil end
		relative, dir = sub( relative, #lowerRoot + 1 ), ""
	end

	local parts = {}
	for part in string.gmatch( dir or "", "[^/]+" ) do parts[ #parts + 1 ] = part end
	for part in string.gmatch( relative, "[^/]+" ) do
		if part == ".." then
			if #parts == 0 then return nil end
			parts[ #parts ] = nil
		elseif part ~= "." then
			parts[ #parts + 1 ] = part
		end
	end
	if #parts == 0 then return nil end
	return concat( parts, "/" )
end

--- The mod folder a texture path lies in, when it lies in one this file reads
--- as an enhancement: under rtx-remix/mods, and not AME's own folder, whose
--- contents its writer retires on every server join.
function E.ModOf( path )
	if not isstring( path ) then return nil end
	local folder = match( string.lower( gsub( path, "\\", "/" ) ), "^rtx%-remix/mods/([^/]+)/.+" )
	if not folder or folder == E.OWN_MOD or folder == E.TOPBR_MOD then return nil end
	return folder
end

function E.IsModTexture( path )
	return E.ModOf( path ) ~= nil and string.lower( sub( path, -4 ) ) == ".dds"
end

--- Whether a file exists in the game folder.
function E.Exists( path )
	return isstring( path ) and FS.Exists( path ) == true
end

---------------------------------------------------------------------------
-- USDA: lexer
---------------------------------------------------------------------------
-- Only the text format. Remix mods are written by hand, by the Toolkit and by
-- scripts, and all of them write USDA; the binary crate form is reported.

local T_EOF, T_ID, T_STR, T_NUM, T_ASSET, T_PATH, T_PUNCT = 0, 1, 2, 3, 4, 5, 6

local PUNCT = {
	[ 40 ] = "(", [ 41 ] = ")", [ 91 ] = "[", [ 93 ] = "]", [ 123 ] = "{", [ 125 ] = "}",
	[ 61 ] = "=", [ 44 ] = ",", [ 59 ] = ";", [ 58 ] = ":",
}

local ESCAPES = { n = "\n", t = "\t", r = "\r", [ "\\" ] = "\\", [ "\"" ] = "\"", [ "'" ] = "'" }

local NUMBER_PATTERNS = {
	"^[%-%+]?%d+%.?%d*[eE][%-%+]?%d+",
	"^[%-%+]?%.%d+[eE][%-%+]?%d+",
	"^[%-%+]?%d+%.?%d*",
	"^[%-%+]?%.%d+",
}

local WORD_NUMBERS = { inf = math.huge, [ "-inf" ] = -math.huge, [ "+inf" ] = math.huge }

local function Lex( text )
	local kinds, values, starts = {}, {}, {}
	local n, pos, length = 0, 1, #text

	while true do
		while true do
			local _, stop = find( text, "^[ \t\r\n]+", pos )
			if stop then pos = stop + 1 end
			if byte( text, pos ) ~= 35 then break end
			local newline = find( text, "\n", pos, true )
			if not newline then pos = length + 1 break end
			pos = newline + 1
		end
		if pos > length then break end

		n = n + 1
		starts[ n ] = pos
		local c = byte( text, pos )

		if c == 34 or c == 39 then
			local quote = c == 34 and "\"" or "'"
			local triple = quote .. quote .. quote
			if sub( text, pos, pos + 2 ) == triple then
				local close = find( text, triple, pos + 3, true )
				if not close then return nil, "unterminated string", pos end
				kinds[ n ], values[ n ] = T_STR, sub( text, pos + 3, close - 1 )
				pos = close + 3
			else
				local parts, at = {}, pos + 1
				local stopAt = c == 34 and "[\"\\\n]" or "['\\\n]"
				while true do
					local hit = find( text, stopAt, at )
					if not hit then return nil, "unterminated string", pos end
					local ch = byte( text, hit )
					parts[ #parts + 1 ] = sub( text, at, hit - 1 )
					if ch == 92 then
						local escaped = sub( text, hit + 1, hit + 1 )
						parts[ #parts + 1 ] = ESCAPES[ escaped ] or escaped
						at = hit + 2
					elseif ch == 10 then
						return nil, "line break inside a string", pos
					else
						pos = hit + 1
						break
					end
				end
				kinds[ n ], values[ n ] = T_STR, concat( parts )
			end
		elseif c == 64 then
			if sub( text, pos, pos + 2 ) == "@@@" then
				local close = find( text, "@@@", pos + 3, true )
				if not close then return nil, "unterminated asset path", pos end
				kinds[ n ], values[ n ] = T_ASSET, sub( text, pos + 3, close - 1 )
				pos = close + 3
			else
				local close = find( text, "@", pos + 1, true )
				if not close then return nil, "unterminated asset path", pos end
				kinds[ n ], values[ n ] = T_ASSET, sub( text, pos + 1, close - 1 )
				pos = close + 1
			end
		elseif c == 60 then
			local close = find( text, ">", pos + 1, true )
			if not close then return nil, "unterminated prim path", pos end
			kinds[ n ], values[ n ] = T_PATH, sub( text, pos + 1, close - 1 )
			pos = close + 1
		elseif PUNCT[ c ] then
			kinds[ n ], values[ n ] = T_PUNCT, PUNCT[ c ]
			pos = pos + 1
		else
			local first, last
			if ( c >= 48 and c <= 57 ) or c == 46 or c == 45 or c == 43 then
				for _, pattern in ipairs( NUMBER_PATTERNS ) do
					first, last = find( text, pattern, pos )
					if first then break end
				end
			end

			if first then
				kinds[ n ], values[ n ] = T_NUM, tonumber( sub( text, first, last ) )
				pos = last + 1
			else
				first, last = find( text, "^[%-%+]?[%a_][%w_:%.]*", pos )
				if not first then
					return nil, "unexpected character " .. string.format( "%q", sub( text, pos, pos ) ), pos
				end
				local word = sub( text, first, last )
				if WORD_NUMBERS[ word ] then
					kinds[ n ], values[ n ] = T_NUM, WORD_NUMBERS[ word ]
				else
					kinds[ n ], values[ n ] = T_ID, word
				end
				pos = last + 1
			end
		end
	end

	n = n + 1
	kinds[ n ], starts[ n ] = T_EOF, length + 1
	return kinds, values, starts
end

---------------------------------------------------------------------------
-- USDA: parser
---------------------------------------------------------------------------
-- A layer is { meta = {...}, root = prim }; a prim is { spec, type, name,
-- meta, props = { [name] = property }, children = { [name] = prim }, order }.
-- Variant sets are skipped whole: Remix material layers do not use them, and
-- picking a variant would need the composed stage's selections.

E.NONE = E.NONE or setmetatable( {}, { __tostring = function() return "None" end } )

local SPECIFIERS = { def = true, over = true, class = true }
local LIST_OPS   = { prepend = true, append = true, add = true, delete = true, reorder = true }

local function NewPrim( spec, typeName, name )
	return { spec = spec, type = typeName, name = name, props = {}, children = {}, order = {} }
end

local function ParseError( message, at ) error( { usda = true, message = message, at = at }, 0 ) end

local function Parse( text )
	local K, V, P = Lex( text )
	if not K then ParseError( V, P ) end

	local i = 1

	local function Punct( value ) return K[ i ] == T_PUNCT and V[ i ] == value end

	local function Expect( value )
		if not Punct( value ) then ParseError( "expected '" .. value .. "'", P[ i ] ) end
		i = i + 1
	end

	-- Skips one bracketed group, whatever it contains.
	local function SkipGroup()
		local depth = 0
		repeat
			local k, v = K[ i ], V[ i ]
			if k == T_EOF then ParseError( "unterminated group", P[ i ] ) end
			if k == T_PUNCT then
				if v == "(" or v == "[" or v == "{" then depth = depth + 1
				elseif v == ")" or v == "]" or v == "}" then depth = depth - 1 end
			end
			i = i + 1
		until depth == 0
	end

	local ParseValue, ParseDictionary

	ParseValue = function()
		local k, v = K[ i ], V[ i ]

		if k == T_NUM or k == T_STR then
			i = i + 1
			return v
		elseif k == T_ASSET then
			i = i + 1
			local value = { asset = v }
			-- A reference: the layer, then the prim in it.
			if K[ i ] == T_PATH then value.path = V[ i ] i = i + 1 end
			return value
		elseif k == T_PATH then
			i = i + 1
			return { path = v }
		elseif k == T_ID then
			i = i + 1
			if v == "None" then return E.NONE end
			if v == "true" then return true end
			if v == "false" then return false end
			if v == "nan" then return 0 / 0 end
			return v
		elseif Punct( "(" ) or Punct( "[" ) then
			local close = Punct( "(" ) and ")" or "]"
			i = i + 1
			local out = {}
			while not Punct( close ) do
				if K[ i ] == T_EOF then ParseError( "unterminated list", P[ i ] ) end
				out[ #out + 1 ] = ParseValue()
				-- A sublayer or reference carries its layer offset in parentheses.
				if close == "]" and Punct( "(" ) then SkipGroup() end
				if Punct( "," ) then i = i + 1 end
			end
			i = i + 1
			return out
		elseif Punct( "{" ) then
			return ParseDictionary()
		end

		ParseError( "unexpected value", P[ i ] )
	end

	-- Typed entries (`float x = 1`, `dictionary d = {...}`) in metadata, and
	-- `time: value` pairs in timeSamples.
	ParseDictionary = function()
		Expect( "{" )
		local out = {}
		while not Punct( "}" ) do
			local k = K[ i ]
			if k == T_EOF then ParseError( "unterminated dictionary", P[ i ] ) end

			if ( k == T_NUM or k == T_STR ) and K[ i + 1 ] == T_PUNCT and V[ i + 1 ] == ":" then
				local key = V[ i ]
				i = i + 2
				out[ key ] = ParseValue()
			elseif k == T_ID then
				local first = V[ i ]
				i = i + 1
				if Punct( "[" ) and K[ i + 1 ] == T_PUNCT and V[ i + 1 ] == "]" then i = i + 2 end
				local key = first
				if K[ i ] == T_ID or K[ i ] == T_STR then
					key = V[ i ]
					i = i + 1
				end
				Expect( "=" )
				out[ key ] = ParseValue()
			elseif Punct( "," ) or Punct( ";" ) then
				i = i + 1
			else
				ParseError( "unexpected dictionary entry", P[ i ] )
			end
		end
		i = i + 1
		return out
	end

	local function ParseMetadata()
		Expect( "(" )
		local meta = {}
		while not Punct( ")" ) do
			local k, v = K[ i ], V[ i ]
			if k == T_EOF then ParseError( "unterminated metadata", P[ i ] ) end

			if k == T_STR then
				meta.doc = v
				i = i + 1
			elseif k == T_ID then
				i = i + 1
				local key, op = v, nil
				if LIST_OPS[ v ] and K[ i ] == T_ID then
					op, key = v, V[ i ]
					i = i + 1
				end
				Expect( "=" )
				local value = ParseValue()
				if Punct( "(" ) then SkipGroup() end

				-- References: an explicit list replaces, the list editing forms
				-- add. Delete is ignored rather than guessed at.
				if op == nil or op == "prepend" or op == "append" or op == "add" then
					if op and istable( meta[ key ] ) and istable( value ) then
						local merged = {}
						local first, second = meta[ key ], value
						if op == "prepend" then first, second = value, meta[ key ] end
						for _, item in ipairs( first.asset == nil and first.path == nil and first or { first } ) do merged[ #merged + 1 ] = item end
						for _, item in ipairs( second.asset == nil and second.path == nil and second or { second } ) do merged[ #merged + 1 ] = item end
						meta[ key ] = merged
					else
						meta[ key ] = value
					end
				end
			elseif Punct( ";" ) or Punct( "," ) then
				i = i + 1
			else
				ParseError( "unexpected metadata entry", P[ i ] )
			end
		end
		i = i + 1
		return meta
	end

	local ParsePrim

	local function ParseProperty( prim )
		local uniform = false
		while K[ i ] == T_ID and ( V[ i ] == "custom" or V[ i ] == "uniform"
			or V[ i ] == "varying" or LIST_OPS[ V[ i ] ] ) do
			if V[ i ] == "uniform" then uniform = true end
			i = i + 1
		end

		if K[ i ] ~= T_ID then ParseError( "expected a property type", P[ i ] ) end
		local typeName = V[ i ]
		i = i + 1
		if Punct( "[" ) and K[ i + 1 ] == T_PUNCT and V[ i + 1 ] == "]" then
			typeName = typeName .. "[]"
			i = i + 2
		end

		if K[ i ] ~= T_ID then ParseError( "expected a property name", P[ i ] ) end
		local name = V[ i ]
		i = i + 1

		local property = { type = typeName, uniform = uniform }
		if Punct( "=" ) then
			i = i + 1
			property.value = ParseValue()
			property.hasValue = true
		end
		if Punct( "(" ) then property.meta = ParseMetadata() end

		-- One layer may not author a property twice; the first one is kept.
		if not prim.props[ name ] then prim.props[ name ] = property end
	end

	local function ParseBody( prim )
		while not Punct( "}" ) do
			local k, v = K[ i ], V[ i ]
			if k == T_EOF then ParseError( "unterminated prim", P[ i ] ) end

			if k == T_ID and SPECIFIERS[ v ] then
				ParsePrim( prim )
			elseif k == T_ID and v == "variantSet" then
				i = i + 2
				Expect( "=" )
				SkipGroup()
			elseif k == T_ID and v == "reorder" and K[ i + 1 ] == T_ID
				and ( V[ i + 1 ] == "nameChildren" or V[ i + 1 ] == "properties" ) then
				i = i + 2
				Expect( "=" )
				ParseValue()
			elseif k == T_ID then
				ParseProperty( prim )
			elseif Punct( ";" ) then
				i = i + 1
			else
				ParseError( "unexpected token in a prim", P[ i ] )
			end
		end
	end

	ParsePrim = function( parent )
		local spec = V[ i ]
		i = i + 1
		local typeName
		if K[ i ] == T_ID then
			typeName = V[ i ]
			i = i + 1
		end
		if K[ i ] ~= T_STR then ParseError( "expected a prim name", P[ i ] ) end
		local name = V[ i ]
		i = i + 1

		local prim = NewPrim( spec, typeName, name )
		if Punct( "(" ) then prim.meta = ParseMetadata() end
		Expect( "{" )
		ParseBody( prim )
		Expect( "}" )

		if not parent.children[ name ] then
			parent.children[ name ] = prim
			parent.order[ #parent.order + 1 ] = name
		end
	end

	local layer = { meta = {}, root = NewPrim( "def", nil, "" ) }
	if Punct( "(" ) then layer.meta = ParseMetadata() end

	while K[ i ] ~= T_EOF do
		local v = V[ i ]
		if K[ i ] == T_ID and SPECIFIERS[ v ] then
			ParsePrim( layer.root )
		elseif K[ i ] == T_ID and v == "reorder" then
			i = i + 2
			Expect( "=" )
			ParseValue()
		else
			ParseError( "unexpected token at the top of the layer", P[ i ] )
		end
	end

	return layer
end

--- A parsed USDA layer, or nil plus a message naming the line.
function E.ParseUSDA( text )
	if not isstring( text ) then return nil, "no text" end
	if sub( text, 1, 8 ) == "PXR-USDC" then
		return nil, "binary USD (USDC) layers cannot be read"
	end

	local ok, result = pcall( Parse, text )
	if ok then return result end

	if istable( result ) and result.usda then
		local line = 1
		for _ in string.gmatch( sub( text, 1, ( result.at or 1 ) - 1 ), "\n" ) do line = line + 1 end
		return nil, string.format( "line %d: %s", line, tostring( result.message ) )
	end
	return nil, tostring( result )
end

local function FindPrim( root, path )
	if not isstring( path ) then return nil end
	local prim = root
	for part in string.gmatch( path, "[^/]+" ) do
		prim = prim and prim.children[ part ]
		if not prim then return nil end
	end
	return prim ~= root and prim or nil
end

-- A references/subLayers value as a list of { asset, path } items.
local function ItemList( value )
	if not istable( value ) then return {} end
	if value.asset ~= nil or value.path ~= nil then return { value } end
	return value
end

---------------------------------------------------------------------------
-- Layers and mods
---------------------------------------------------------------------------

local function LoadLayer( path )
	local stamp, size = Stamp( path )
	if not stamp then return nil, "missing" end

	local cached = E.LayerCache[ path ]
	if cached and cached.stamp == stamp then return cached.layer, cached.err end

	local layer, err
	if size > MAX_LAYER_BYTES then
		err = "larger than " .. floor( MAX_LAYER_BYTES / 1048576 ) .. " MB"
	else
		local text = FS.Read( path )
		if not isstring( text ) then
			err = "unreadable"
		else
			layer, err = E.ParseUSDA( text )
		end
	end

	E.LayerCache[ path ] = { stamp = stamp, layer = layer or false, err = err }
	return layer, err
end

local USD_EXTENSIONS = { usd = true, usda = true, usdc = true, usdz = true }

-- The file Remix opens for a mod folder: the first entry whose stem is
-- exactly "mod" and whose extension is a USD one.
local function ModFile( folder )
	local files = FS.Find( E.MODS_DIR .. "/" .. folder .. "/mod.*" ) or {}
	table.sort( files )
	for _, name in ipairs( files ) do
		local stem, extension = match( name, "^(.-)%.([^%.]+)$" )
		if stem == "mod" and USD_EXTENSIONS[ extension ] then
			return E.MODS_DIR .. "/" .. folder .. "/" .. name
		end
	end
	return nil
end

-- Root first, then each sublayer followed by its own sublayers: USD's
-- strength order, strongest first.
local function LayerStack( rootPath )
	local stack, errors, seen = {}, {}, {}

	local function Visit( path, depth )
		if seen[ string.lower( path ) ] or #stack >= MAX_STACK or depth > 32 then return end
		seen[ string.lower( path ) ] = true

		local layer, err = LoadLayer( path )
		if not layer then
			errors[ #errors + 1 ] = BaseName( path ) .. ": " .. tostring( err )
			return
		end

		local entry = { path = path, dir = DirOf( path ), layer = layer }
		stack[ #stack + 1 ] = entry

		for _, item in ipairs( ItemList( layer.meta.subLayers ) ) do
			local child = isstring( item.asset ) and E.JoinPath( entry.dir, item.asset )
			if child then
				Visit( child, depth + 1 )
			elseif isstring( item.asset ) then
				errors[ #errors + 1 ] = BaseName( path ) .. ": sublayer " .. item.asset .. " is outside the game folder"
			end
		end
	end

	Visit( rootPath, 0 )
	return stack, errors
end

-- The hash in a material prim's name, the way the runtime reads it: hex
-- digits straight after "mat_".
local function MaterialHash( name )
	local hex = match( name, "^mat_(%x+)" )
	if not hex or #hex > 16 then return nil end
	hex = string.upper( string.rep( "0", 16 - #hex ) .. hex )
	if hex == "0000000000000000" then return nil end
	return hex
end

local function NewMaterial( hash, name, folder )
	return {
		hash = hash, name = name, mod = folder,
		inputs = {}, layers = {}, refs = {}, shaderFound = false,
	}
end

-- An asset path as the runtime resolves it: against the layer that authored
-- it, and for a bare name (no ./ or ../) also against the mod folder, which
-- Remix adds to its asset search path.
local function ResolveAsset( entry, asset, modRoot )
	if not isstring( asset ) or asset == "" then return nil end
	local resolved = E.JoinPath( entry.dir, asset )
	local bare = not find( asset, "^%.%.?[/\\]" ) and not find( asset, "^%a:" )
		and sub( asset, 1, 1 ) ~= "/" and sub( asset, 1, 1 ) ~= "\\"
	if bare and modRoot and ( not resolved or not FS.Exists( resolved ) ) then
		local fromRoot = E.JoinPath( modRoot, asset )
		if fromRoot and FS.Exists( fromRoot ) then return fromRoot end
	end
	return resolved
end

local AddPrimOpinions

local function AddShaderOpinions( material, shader, entry, modRoot )
	for name, property in pairs( shader.props ) do
		if property.hasValue and material.inputs[ name ] == nil then
			local opinion = {
				type = property.type, value = property.value, layer = entry.path,
				colorSpace = property.meta and property.meta.colorSpace or nil,
			}
			if property.type == "asset" and istable( property.value ) and property.value.asset then
				opinion.asset = property.value.asset
				opinion.resolved = ResolveAsset( entry, property.value.asset, modRoot )
			end
			material.inputs[ name ] = opinion
		end
	end
end

AddPrimOpinions = function( material, prim, entry, modRoot )
	local meta = prim.meta or {}
	if material.active == nil and meta.active ~= nil then material.active = meta.active == true end

	for _, item in ipairs( ItemList( meta.references ) ) do
		material.refs[ #material.refs + 1 ] = { asset = item.asset, path = item.path, from = entry }
	end

	local seenLayer = false
	for _, path in ipairs( material.layers ) do
		if path == entry.path then seenLayer = true break end
	end
	if not seenLayer then material.layers[ #material.layers + 1 ] = entry.path end

	-- The runtime takes the child called Shader, or failing that the first
	-- child that is a Shader prim.
	local shader = prim.children.Shader
	if not shader then
		for _, name in ipairs( prim.order ) do
			if prim.children[ name ].type == "Shader" then shader = prim.children[ name ] break end
		end
	end
	if shader then
		material.shaderFound = true
		AddShaderOpinions( material, shader, entry, modRoot )
	end
end

-- References are weaker than every local opinion, so they are applied after
-- the whole layer stack, strongest reference first.
local function AddReferences( material, modRoot, depth )
	local refs = material.refs
	material.refs = {}
	if depth > MAX_REF_DEPTH then return end

	for _, ref in ipairs( refs ) do
		local path = ref.asset and E.JoinPath( ref.from.dir, ref.asset ) or ref.from.path
		local layer = path and LoadLayer( path )
		if layer then
			local primPath = ref.path
			if not primPath and isstring( layer.meta.defaultPrim ) then primPath = "/" .. layer.meta.defaultPrim end
			local prim = FindPrim( layer.root, primPath )
			if prim then
				AddPrimOpinions( material, prim, { path = path, dir = DirOf( path ), layer = layer }, modRoot )
			end
		end
	end

	if #material.refs > 0 then AddReferences( material, modRoot, depth + 1 ) end
end

local function Classify( material )
	local source = material.inputs[ "info:mdl:sourceAsset" ]
	local asset = source and istable( source.value ) and source.value.asset or nil
	material.shaderAsset = isstring( asset ) and asset or nil

	material.kind = "opaque"
	if material.shaderAsset then
		if find( material.shaderAsset, "AperturePBR_Portal.mdl", 1, true ) then
			material.kind = "portal"
		elseif find( material.shaderAsset, "AperturePBR_Translucent.mdl", 1, true ) then
			material.kind = material.inputs.rayPortalIndex and "portal" or "translucent"
		end
	end

	-- A prim with no shader claims nothing: the runtime moves on to the next mod.
	material.valid = material.shaderFound and material.active ~= false
end

local function ComposeMod( record )
	local stack, errors = LayerStack( record.file )
	record.stack, record.errors = stack, errors
	record.materials, record.order = {}, {}
	local modRoot = E.MODS_DIR .. "/" .. record.folder

	for _, entry in ipairs( stack ) do
		local rootNode = entry.layer.root.children.RootNode
		local looks = rootNode and rootNode.children.Looks
		if looks then
			for _, name in ipairs( looks.order ) do
				local hash = MaterialHash( name )
				if hash then
					local material = record.materials[ hash ]
					if not material then
						material = NewMaterial( hash, name, record.folder )
						record.materials[ hash ] = material
						record.order[ #record.order + 1 ] = hash
					end
					AddPrimOpinions( material, looks.children[ name ], entry, modRoot )
				end
			end
		end
	end

	local count = 0
	for _, hash in ipairs( record.order ) do
		local material = record.materials[ hash ]
		AddReferences( material, modRoot, 1 )
		Classify( material )
		if material.valid then count = count + 1 end
	end
	record.count = count
end

-- What a mod's composed result depends on: the stamp of every layer read.
local function StackStamp( record )
	local parts = {}
	for _, entry in ipairs( record.stack or {} ) do
		parts[ #parts + 1 ] = Stamp( entry.path ) or "missing"
	end
	return concat( parts, "|" )
end

--- Read every mod again if anything changed. `force` ignores the throttle.
function E.Refresh( force )
	local now = Clock()
	if not force and E.LastRefresh and now - E.LastRefresh < REFRESH_SECONDS then return false end
	E.LastRefresh = now

	local started = Clock()
	local _, folders = FS.Find( E.MODS_DIR .. "/*" )
	folders = istable( folders ) and folders or {}

	-- The runtime's order: byte by byte, upper case before lower.
	table.sort( folders )

	local mods, changed, seen = {}, false, {}
	for _, folder in ipairs( folders ) do
		seen[ folder ] = true
		local file = ModFile( folder )
		if file then
			local record = E.ModCache[ folder ]
			if not record or record.file ~= file or record.stamp ~= StackStamp( record ) then
				record = { folder = folder, file = file, own = folder == E.OWN_MOD, automatic = folder == E.TOPBR_MOD }
				ComposeMod( record )
				record.stamp = StackStamp( record )
				E.ModCache[ folder ] = record
				changed = true
			end
			mods[ #mods + 1 ] = record
		end
	end

	for folder in pairs( E.ModCache ) do
		if not seen[ folder ] then
			E.ModCache[ folder ] = nil
			changed = true
		end
	end
	if #mods ~= #E.Mods then changed = true end

	E.Mods = mods
	E.LastScanMS = floor( ( Clock() - started ) * 1000 + 0.5 )
	if changed then E.Generation = E.Generation + 1 end
	return changed
end

local function NormalizeHash( raw )
	if not isstring( raw ) then return nil end
	local hex = string.upper( string.Trim( raw ) )
	hex = gsub( hex, "^0X", "" )
	if hex == "" or #hex > 16 or find( hex, "[^0-9A-F]" ) then return nil end
	hex = string.rep( "0", 16 - #hex ) .. hex
	if hex == "0000000000000000" then return nil end
	return hex
end

--- Every mod replacing any of `hashes`, in the runtime's order.
---
---   entries      { mod, folder, hash, material, own, automatic, rank }
---   effective    the entry Remix draws for the first hash
---   enhancement  the first entry that is not AME's own: what an AME profile
---                for this material should start from
---   automatic    the client's ToPBR layer when that is the enhancement; its
---                maps cannot be carried (the schema refuses ~gmod_topbr)
function E.Lookup( hashes )
	E.Refresh()

	local wanted, list = {}, {}
	for _, raw in ipairs( istable( hashes ) and hashes or { hashes } ) do
		local hash = NormalizeHash( raw )
		if hash and not wanted[ hash ] then
			wanted[ hash ] = true
			list[ #list + 1 ] = hash
		end
	end
	table.sort( list )

	local result = { hashes = list, entries = {} }
	if #list == 0 then return result end

	for rank, record in ipairs( E.Mods ) do
		for _, hash in ipairs( list ) do
			local material = record.materials[ hash ]
			if material and material.valid then
				result.entries[ #result.entries + 1 ] = {
					folder = record.folder, hash = hash, material = material, rank = rank,
					own = record.own, automatic = record.automatic,
				}
			end
		end
	end

	local primary = list[ 1 ]
	for _, entry in ipairs( result.entries ) do
		if entry.hash == primary then
			result.effective = result.effective or entry
			if not entry.own then
				if entry.automatic then
					result.automatic = result.automatic or entry
				elseif not result.enhancement and not result.automatic then
					result.enhancement = entry
				end
			end
		end
	end
	-- ToPBR sorts last, so it can only be "the enhancement" when nothing else
	-- replaces this hash. Then there is nothing to carry from it.
	if result.automatic and result.enhancement then result.automatic = nil end

	return result
end

---------------------------------------------------------------------------
-- From USD inputs to an AME profile
---------------------------------------------------------------------------

local MAP_INPUTS = {
	{ "diffuse_texture",                      "albedo" },
	{ "normalmap_texture",                    "normal" },
	{ "reflectionroughness_texture",          "roughness" },
	{ "metallic_texture",                     "metallic" },
	{ "height_texture",                       "height" },
	{ "emissive_mask_texture",                "emissive" },
	{ "anisotropy_texture",                   "anisotropy" },
	{ "subsurface_transmittance_texture",     "subsurface_transmittance" },
	{ "subsurface_thickness_texture",         "subsurface_thickness" },
	{ "subsurface_single_scattering_texture", "subsurface_scattering" },
	{ "subsurface_radius_texture",            "subsurface_radius" },
}

-- USD input -> AME constant, its kind and AME's range. Inputs the runtime
-- clamps more loosely than AME's schema are reported when they are clamped.
local CONSTANT_INPUTS = {
	diffuse_color_constant              = { "albedo", "color", 0, 1 },
	opacity_constant                    = { "opacity", "number", 0, 1 },
	reflection_roughness_constant       = { "roughness", "number", 0, 1 },
	metallic_constant                   = { "metallic", "number", 0, 1 },
	emissive_color_constant             = { "emissive_color", "color", 0, 1 },
	emissive_intensity                  = { "emissive_intensity", "number", 0, 65504 },
	anisotropy_constant                 = { "anisotropy", "number", -1, 1 },
	anisotropy                          = { "anisotropy", "number", -1, 1 },
	thin_film_thickness_constant        = { "thin_film_thickness", "number", 0, 1500 },
	displace_in                         = { "displace_in", "number", 0, 0.2 },
	displace_out                        = { "displace_out", "number", 0, 0.2 },
	subsurface_transmittance_color      = { "subsurface_transmittance_color", "color", 0, 1 },
	subsurface_measurement_distance     = { "subsurface_measurement_distance", "number", 0, 16 },
	subsurface_single_scattering_albedo = { "subsurface_single_scattering_albedo", "color", 0, 1 },
	subsurface_volumetric_anisotropy    = { "subsurface_volumetric_anisotropy", "number", -0.99, 0.99 },
	subsurface_radius                   = { "subsurface_radius", "color", 0, 1 },
	subsurface_radius_scale             = { "subsurface_radius_scale", "number", 0, 1000 },
	subsurface_max_sample_radius        = { "subsurface_max_sample_radius", "number", 0, 65504 },
}

local FILTER_MODES = { [ 0 ] = "nearest", [ 1 ] = "linear" }
local WRAP_MODES   = { [ 0 ] = "clamp", [ 1 ] = "repeat", [ 2 ] = "mirror", [ 3 ] = "clip" }
local ENCODINGS    = { [ 0 ] = "octahedral", [ 1 ] = "tangent_space_ogl", [ 2 ] = "tangent_space_dx" }
local BLEND_TYPES  = {
	[ 0 ] = "alpha", [ 1 ] = "alpha_emissive", [ 2 ] = "reverse_alpha_emissive", [ 3 ] = "color",
	[ 4 ] = "color_emissive", [ 5 ] = "reverse_color_emissive", [ 6 ] = "emissive",
	[ 7 ] = "multiplicative", [ 8 ] = "double_multiplicative",
}
local ALPHA_TESTS  = {
	[ 0 ] = "none", [ 1 ] = "never", [ 2 ] = "less", [ 3 ] = "equal", [ 4 ] = "less_equal",
	[ 5 ] = "greater", [ 6 ] = "not_equal", [ 7 ] = "greater_equal",
}

-- USD input -> AME option. Unauthored options take the runtime's default,
-- which is not always AME's: textures are not preloaded, and a normal map is
-- octahedral, unless the layer says otherwise.
local OPTION_INPUTS = {
	filter_mode                           = { "filter_mode", "enum", FILTER_MODES },
	wrap_mode_u                           = { "wrap_u", "enum", WRAP_MODES },
	wrap_mode_v                           = { "wrap_v", "enum", WRAP_MODES },
	encoding                              = { "normal_encoding", "enum", ENCODINGS },
	blend_type                            = { "blend_type", "enum", BLEND_TYPES },
	alpha_test_type                       = { "alpha_test_type", "enum", ALPHA_TESTS },
	alpha_test_reference_value            = { "alpha_reference", "alpha" },
	thin_film_thickness_from_albedo_alpha = { "alpha_is_thin_film", "bool" },
	use_legacy_alpha_state                = { "use_draw_call_alpha", "bool" },
	inverted_blend                        = { "inverted_blend", "bool" },
	blend_enabled                         = { "blend_enabled", "bool" },
	enable_thin_film                      = { "enable_thin_film", "bool" },
	enable_emission                       = { "enable_emission", "bool" },
	preload_textures                      = { "preload_textures", "bool" },
	ignore_material                       = { "ignore_material", "bool" },
	subsurface_diffusion_profile          = { "subsurface_diffusion_profile", "bool" },
	sprite_sheet_rows                     = { "sprite_sheet_rows", "count", 1 },
	sprite_sheet_cols                     = { "sprite_sheet_columns", "count", 1 },
	sprite_sheet_fps                      = { "sprite_sheet_fps", "count", 0 },
}

local OPTION_DEFAULTS = {
	filter_mode = "linear", wrap_u = "repeat", wrap_v = "repeat",
	normal_encoding = "octahedral", alpha_is_thin_film = false,
	use_draw_call_alpha = true, inverted_blend = false, blend_enabled = false,
	alpha_test_type = "none", alpha_reference = 0, enable_thin_film = false,
	enable_emission = false, preload_textures = false, ignore_material = false,
	subsurface_diffusion_profile = false,
	sprite_sheet_rows = 1, sprite_sheet_columns = 1, sprite_sheet_fps = 0,
}

-- Inputs that are not material values at all.
local IGNORED_INPUTS = {
	[ "info:mdl:sourceAsset" ] = true, [ "info:mdl:sourceAsset:subIdentifier" ] = true,
	[ "info:implementationSource" ] = true, [ "info:id" ] = true,
}

local function Scalar( value )
	if isnumber( value ) then return value end
	if isbool( value ) then return value and 1 or 0 end
	if istable( value ) and isnumber( value[ 1 ] ) and value[ 2 ] == nil then return value[ 1 ] end
	return nil
end

local function Finite( value )
	return isnumber( value ) and value == value and value ~= math.huge and value ~= -math.huge
end

local function ColorValue( value )
	local grey = Scalar( value )
	if grey then return { r = grey, g = grey, b = grey } end
	if istable( value ) and isnumber( value[ 1 ] ) and isnumber( value[ 2 ] ) and isnumber( value[ 3 ] ) then
		return { r = value[ 1 ], g = value[ 2 ], b = value[ 3 ] }
	end
	return nil
end

local function Clamped( value, lo, hi )
	if value < lo then return lo, true end
	if value > hi then return hi, true end
	return value, false
end

--- The PBR side of an AME profile for an enhancement material, and what did
--- not fit.
---
---   notes.unsupported  inputs AME has no field for (dropped on Save)
---   notes.clamped      inputs outside AME's range
---   notes.missing      map files that do not exist (left out)
---   notes.foreign      map files AME cannot name (outside the game folder,
---                      or inside the client's ToPBR output)
function E.Seed( material )
	local pbr = { constants = {}, maps = {}, options = {} }
	local notes = {
		unsupported = {}, clamped = {}, missing = {}, foreign = {},
		kind = material.kind, shader = material.shaderAsset, folder = material.mod,
	}
	local handled = {}
	local schema = AdvMat.RTXSchema

	for _, pair in ipairs( MAP_INPUTS ) do
		local name = "inputs:" .. pair[ 1 ]
		local opinion = material.inputs[ name ]
		if opinion then
			handled[ name ] = true
			local path = opinion.resolved
			local clean = path and schema and schema.SanitizeMap and ( schema.SanitizeMap( path ) )
			if opinion.value == E.NONE or not opinion.asset or opinion.asset == "" then
				-- An emptied input: nothing to carry.
			elseif not path or not clean then
				notes.foreign[ #notes.foreign + 1 ] = pair[ 1 ]
			elseif not FS.Exists( path ) then
				notes.missing[ #notes.missing + 1 ] = path
			else
				pbr.maps[ pair[ 2 ] ] = path
			end
		end
	end

	for input, spec in pairs( CONSTANT_INPUTS ) do
		local name = "inputs:" .. input
		local opinion = material.inputs[ name ]
		if opinion then
			handled[ name ] = true
			local value
			if spec[ 2 ] == "color" then
				value = ColorValue( opinion.value )
				if value and Finite( value.r ) and Finite( value.g ) and Finite( value.b ) then
					local a, b, c
					value.r, a = Clamped( value.r, spec[ 3 ], spec[ 4 ] )
					value.g, b = Clamped( value.g, spec[ 3 ], spec[ 4 ] )
					value.b, c = Clamped( value.b, spec[ 3 ], spec[ 4 ] )
					if a or b or c then notes.clamped[ #notes.clamped + 1 ] = input end
				else
					value = nil
				end
			else
				value = Scalar( opinion.value )
				if Finite( value ) then
					local clamped
					value, clamped = Clamped( value, spec[ 3 ], spec[ 4 ] )
					if clamped then notes.clamped[ #notes.clamped + 1 ] = input end
				else
					value = nil
				end
			end
			-- anisotropy_constant (the MDL name) wins over anisotropy (the
			-- runtime's) when a layer authors both.
			if value ~= nil and ( input ~= "anisotropy" or pbr.constants.anisotropy == nil ) then
				pbr.constants[ spec[ 1 ] ] = value
			end
		end
	end

	for key, value in pairs( OPTION_DEFAULTS ) do pbr.options[ key ] = value end

	for input, spec in pairs( OPTION_INPUTS ) do
		local name = "inputs:" .. input
		local opinion = material.inputs[ name ]
		if opinion then
			handled[ name ] = true
			local raw = Scalar( opinion.value )
			local value
			if spec[ 2 ] == "enum" then
				value = Finite( raw ) and spec[ 3 ][ floor( raw ) ] or nil
			elseif spec[ 2 ] == "bool" then
				if Finite( raw ) then value = raw ~= 0 end
			elseif spec[ 2 ] == "count" then
				if Finite( raw ) then value = max( spec[ 3 ], min( 255, floor( raw ) ) ) end
			elseif spec[ 2 ] == "alpha" then
				-- The runtime keeps a byte; a real in [0, 1] is the MDL's alpha.
				if Finite( raw ) then
					if opinion.type ~= "uchar" and opinion.type ~= "int" and raw >= 0 and raw <= 1 then
						value = raw
					else
						value = max( 0, min( 255, raw ) ) / 255
					end
				end
			end
			if value ~= nil then pbr.options[ spec[ 1 ] ] = value end
		end
	end

	-- Blending off is AME's "opaque"; a type authored while it is off is kept
	-- by the runtime but has no effect, which is exactly what opaque says.
	if not pbr.options.blend_enabled then
		pbr.options.blend_type = "opaque"
	elseif not material.inputs[ "inputs:blend_type" ] then
		pbr.options.blend_type = "alpha"
	end

	for name, opinion in pairs( material.inputs ) do
		if not handled[ name ] and not IGNORED_INPUTS[ name ] and opinion.value ~= E.NONE
			and sub( name, 1, 7 ) == "inputs:" and not find( name, "%.connect$" ) then
			notes.unsupported[ #notes.unsupported + 1 ] = sub( name, 8 )
		end
	end
	table.sort( notes.unsupported )
	table.sort( notes.clamped )

	return pbr, notes
end

--- A short name for a layer path inside its mod: "models/robin_69c55742.usda".
function E.LayerName( material )
	local path = material and material.layers and material.layers[ 1 ]
	if not path then return "?" end
	local prefix = E.MODS_DIR .. "/" .. material.mod .. "/"
	if sub( string.lower( path ), 1, #prefix ) == string.lower( prefix ) then return sub( path, #prefix + 1 ) end
	return path
end

--- "ai_pbr: textures/x.a.rtex.dds" for a map row.
function E.Describe( path )
	local folder = E.ModOf( path )
	if not folder then return path end
	return folder .. ": " .. sub( path, #E.MODS_DIR + #folder + 3 )
end

---------------------------------------------------------------------------
-- DDS headers
---------------------------------------------------------------------------

local function U32( data, at )
	local a, b, c, d = byte( data, at, at + 3 )
	return a + b * 256 + c * 65536 + d * 16777216
end

local FOURCC = {
	DXT1 = "bc1", DXT2 = "bc2", DXT3 = "bc2", DXT4 = "bc3", DXT5 = "bc3",
	ATI1 = "bc4", BC4U = "bc4", ATI2 = "bc5", BC5U = "bc5",
}

local DXGI = {
	[ 70 ] = "bc1", [ 71 ] = "bc1", [ 72 ] = "bc1",
	[ 73 ] = "bc2", [ 74 ] = "bc2", [ 75 ] = "bc2",
	[ 76 ] = "bc3", [ 77 ] = "bc3", [ 78 ] = "bc3",
	[ 79 ] = "bc4", [ 80 ] = "bc4",
	[ 82 ] = "bc5", [ 83 ] = "bc5",
	[ 97 ] = "bc7", [ 98 ] = "bc7", [ 99 ] = "bc7",
	[ 27 ] = "rgba8", [ 28 ] = "rgba8", [ 29 ] = "rgba8",
	[ 87 ] = "bgra8", [ 90 ] = "bgra8", [ 91 ] = "bgra8",
	[ 88 ] = "bgrx8", [ 92 ] = "bgrx8", [ 93 ] = "bgrx8",
	[ 60 ] = "r8", [ 61 ] = "r8",
	[ 48 ] = "rg8", [ 49 ] = "rg8",
	[ 65 ] = "a8",
}

-- block: bytes per 4x4 block; bpp: bytes per pixel. alpha: whether the format
-- can carry transparency; channels: 1 for single-channel maps, 2 for
-- two-channel normal formats.
local FORMATS = {
	bc1   = { block = 8,  alpha = true },
	bc2   = { block = 16, alpha = true },
	bc3   = { block = 16, alpha = true },
	bc4   = { block = 8,  channels = 1 },
	bc5   = { block = 16, channels = 2 },
	bc7   = { block = 16, alpha = true },
	rgba8 = { bpp = 4, alpha = true },
	bgra8 = { bpp = 4, alpha = true },
	bgrx8 = { bpp = 4 },
	rgbx8 = { bpp = 4 },
	bgr8  = { bpp = 3 },
	r8    = { bpp = 1, channels = 1 },
	l8    = { bpp = 1, channels = 1 },
	rg8   = { bpp = 2, channels = 2 },
	l8a8  = { bpp = 2, alpha = true },
	a8    = { bpp = 1, alpha = true },
}

local function LegacyFormat( flags, bits, rMask, gMask, bMask, aMask )
	local hasAlpha = flags % 2 == 1
	if floor( flags / 64 ) % 2 == 1 then
		if bits == 32 and rMask == 0x00ff0000 and gMask == 0x0000ff00 and bMask == 0x000000ff then
			return ( hasAlpha and aMask == 0xff000000 ) and "bgra8" or "bgrx8"
		end
		if bits == 32 and rMask == 0x000000ff and gMask == 0x0000ff00 and bMask == 0x00ff0000 then
			return ( hasAlpha and aMask == 0xff000000 ) and "rgba8" or "rgbx8"
		end
		if bits == 24 and rMask == 0x00ff0000 and gMask == 0x0000ff00 and bMask == 0x000000ff then
			return "bgr8"
		end
		return nil
	end
	if floor( flags / 131072 ) % 2 == 1 then
		if bits == 8 then return "l8" end
		if bits == 16 and hasAlpha and rMask == 0xff and aMask == 0xff00 then return "l8a8" end
		return nil
	end
	if floor( flags / 2 ) % 2 == 1 and bits == 8 then return "a8" end
	return nil
end

local function ParseHeader( head, fileSize )
	if not isstring( head ) or #head < 128 or sub( head, 1, 4 ) ~= "DDS " then
		return nil, "not a DDS file"
	end
	if U32( head, 5 ) ~= 124 or U32( head, 77 ) ~= 32 then return nil, "DDS header is malformed" end

	local height, width = U32( head, 13 ), U32( head, 17 )
	local flags = U32( head, 9 )
	local mips = 1
	if floor( flags / 131072 ) % 2 == 1 then mips = max( 1, U32( head, 29 ) ) end

	local pfFlags = U32( head, 81 )
	local fourCC = sub( head, 85, 88 )
	local caps2 = U32( head, 113 )
	local offset = 128
	local format, srgb

	if floor( pfFlags / 4 ) % 2 == 1 then
		if fourCC == "DX10" then
			if #head < 148 then return nil, "DDS header is malformed" end
			local dxgi = U32( head, 129 )
			local dimension, arraySize = U32( head, 133 ), U32( head, 141 )
			if dimension ~= 3 or arraySize > 1 or floor( U32( head, 137 ) / 4 ) % 2 == 1 then
				return nil, "only plain 2D DDS textures can be read"
			end
			format = DXGI[ dxgi ]
			srgb = dxgi == 72 or dxgi == 75 or dxgi == 78 or dxgi == 99 or dxgi == 29 or dxgi == 91 or dxgi == 93
			if not format then return nil, "DXGI format " .. dxgi .. " is not supported" end
			offset = 148
		else
			format = FOURCC[ fourCC ]
			if not format then return nil, "DDS format " .. gsub( fourCC, "%c", "?" ) .. " is not supported" end
		end
	else
		format = LegacyFormat( pfFlags, U32( head, 89 ), U32( head, 93 ), U32( head, 97 ), U32( head, 101 ), U32( head, 105 ) )
		if not format then return nil, "this uncompressed DDS layout is not supported" end
	end

	if floor( caps2 / 512 ) % 2 == 1 or floor( caps2 / 2097152 ) % 2 == 1 then
		return nil, "cube maps and volume textures cannot be read"
	end
	if width < 1 or height < 1 or width > 32768 or height > 32768 then
		return nil, "DDS dimensions are invalid"
	end

	local spec = FORMATS[ format ]
	local info = {
		width = width, height = height, format = format, srgb = srgb == true,
		alpha = spec.alpha == true, channels = spec.channels or ( spec.alpha and 4 or 3 ),
		levels = {}, fileSize = fileSize,
	}

	local at, w, h = offset, width, height
	for level = 1, min( mips, 20 ) do
		local size
		if spec.block then
			size = max( 1, floor( ( w + 3 ) / 4 ) ) * max( 1, floor( ( h + 3 ) / 4 ) ) * spec.block
		else
			size = w * h * spec.bpp
		end
		if fileSize and at + size > fileSize then break end
		info.levels[ level ] = { width = w, height = h, offset = at, size = size }
		at = at + size
		if w == 1 and h == 1 then break end
		w, h = max( 1, floor( w / 2 ) ), max( 1, floor( h / 2 ) )
	end
	if #info.levels == 0 then return nil, "DDS file is truncated" end
	return info
end

E.ParseDDSHeader = ParseHeader

--- Header facts about a DDS file in the game folder, or nil plus a reason.
function E.DDSInfo( path )
	if not isstring( path ) then return nil, "no path" end
	local stamp, size = Stamp( path )
	if not stamp then return nil, "the file does not exist" end

	local cached = E.DDSCache[ path ]
	if cached and cached.stamp == stamp then return cached.info, cached.err end

	local info, err = ParseHeader( FS.ReadRange( path, 0, 148 ), size )
	if info then info.stamp = stamp end
	E.DDSCache[ path ] = { stamp = stamp, info = info, err = err }
	return info, err
end

-- The level to decode for an output no larger than `side` on either axis,
-- and the further halvings needed when the file has no small enough mip.
local function PickLevel( info, side, maxBytes )
	local best
	for index, level in ipairs( info.levels ) do
		local fits = level.width <= side and level.height <= side
		-- The writer turns a picture into an uncompressed BGRA chain: 4 bytes a
		-- pixel plus a third for the mips, which has to fit its byte ceiling.
		if fits and maxBytes and level.width * level.height * 16 / 3 > maxBytes then fits = false end
		if fits then best = index break end
	end
	if best then return best, 0 end

	local last = #info.levels
	local w, h, halvings = info.levels[ last ].width, info.levels[ last ].height, 0
	while w > side or h > side or ( maxBytes and w * h * 16 / 3 > maxBytes ) do
		w, h = max( 1, floor( w / 2 ) ), max( 1, floor( h / 2 ) )
		halvings = halvings + 1
		if w == 1 and h == 1 then break end
	end
	return last, halvings
end

---------------------------------------------------------------------------
-- Block decoders
---------------------------------------------------------------------------
-- Each one writes 16 pixels of R, G, B, A into `px` (64 entries, rows top to
-- bottom), from the block starting at byte `at` of `data`. The palette
-- arithmetic follows the usual integer formulas (as Pillow's decoder does),
-- and BC7 follows the D3D11 specification exactly.

local px = {}
local palR, palG, palB, palA = {}, {}, {}, {}
local channelA, channelB = {}, {}
local alphaPal = {}

local function Expand565( c )
	local r = floor( c / 2048 )
	local g = floor( c / 32 ) % 64
	local b = c % 32
	return r * 8 + floor( r / 4 ), g * 4 + floor( g / 16 ), b * 8 + floor( b / 4 )
end

-- The colour half shared by BC1, BC2 and BC3. BC2/BC3 always use the four
-- colour mode; BC1 switches to three colours and transparency when the first
-- endpoint is not the larger one.
local function DecodeColour( data, at, fourColours )
	local b0, b1, b2, b3, i0, i1, i2, i3 = byte( data, at, at + 7 )
	local c0, c1 = b0 + b1 * 256, b2 + b3 * 256
	local r0, g0, bl0 = Expand565( c0 )
	local r1, g1, bl1 = Expand565( c1 )

	palR[ 0 ], palG[ 0 ], palB[ 0 ], palA[ 0 ] = r0, g0, bl0, 255
	palR[ 1 ], palG[ 1 ], palB[ 1 ], palA[ 1 ] = r1, g1, bl1, 255
	if fourColours or c0 > c1 then
		palR[ 2 ], palG[ 2 ], palB[ 2 ], palA[ 2 ] = floor( ( 2 * r0 + r1 ) / 3 ), floor( ( 2 * g0 + g1 ) / 3 ), floor( ( 2 * bl0 + bl1 ) / 3 ), 255
		palR[ 3 ], palG[ 3 ], palB[ 3 ], palA[ 3 ] = floor( ( r0 + 2 * r1 ) / 3 ), floor( ( g0 + 2 * g1 ) / 3 ), floor( ( bl0 + 2 * bl1 ) / 3 ), 255
	else
		palR[ 2 ], palG[ 2 ], palB[ 2 ], palA[ 2 ] = floor( ( r0 + r1 ) / 2 ), floor( ( g0 + g1 ) / 2 ), floor( ( bl0 + bl1 ) / 2 ), 255
		palR[ 3 ], palG[ 3 ], palB[ 3 ], palA[ 3 ] = 0, 0, 0, 0
	end

	local o = 1
	for row = 0, 3 do
		local bits = row == 0 and i0 or row == 1 and i1 or row == 2 and i2 or i3
		for _ = 0, 3 do
			local index = bits % 4
			bits = floor( bits / 4 )
			px[ o ], px[ o + 1 ], px[ o + 2 ], px[ o + 3 ] = palR[ index ], palG[ index ], palB[ index ], palA[ index ]
			o = o + 4
		end
	end
end

-- An 8-byte BC4 block (also BC3's alpha and each half of BC5) into out[1..16].
local function DecodeChannel( data, at, out )
	local a0, a1, b2, b3, b4, b5, b6, b7 = byte( data, at, at + 7 )
	alphaPal[ 0 ], alphaPal[ 1 ] = a0, a1
	if a0 > a1 then
		for k = 1, 6 do alphaPal[ k + 1 ] = floor( ( ( 7 - k ) * a0 + k * a1 ) / 7 ) end
	else
		for k = 1, 4 do alphaPal[ k + 1 ] = floor( ( ( 5 - k ) * a0 + k * a1 ) / 5 ) end
		alphaPal[ 6 ], alphaPal[ 7 ] = 0, 255
	end

	local low = b2 + b3 * 256 + b4 * 65536
	local high = b5 + b6 * 256 + b7 * 65536
	for k = 1, 8 do
		out[ k ] = alphaPal[ low % 8 ]
		low = floor( low / 8 )
	end
	for k = 9, 16 do
		out[ k ] = alphaPal[ high % 8 ]
		high = floor( high / 8 )
	end
end

local function DecodeBC1( data, at ) DecodeColour( data, at, false ) end

local function DecodeBC2( data, at )
	DecodeColour( data, at + 8, true )
	for k = 0, 7 do
		local value = byte( data, at + k )
		px[ k * 8 + 4 ] = ( value % 16 ) * 17
		px[ k * 8 + 8 ] = floor( value / 16 ) * 17
	end
end

local function DecodeBC3( data, at )
	DecodeColour( data, at + 8, true )
	DecodeChannel( data, at, channelA )
	for k = 1, 16 do px[ k * 4 ] = channelA[ k ] end
end

local function DecodeBC4( data, at )
	DecodeChannel( data, at, channelA )
	local o = 1
	for k = 1, 16 do
		local v = channelA[ k ]
		px[ o ], px[ o + 1 ], px[ o + 2 ], px[ o + 3 ] = v, v, v, 255
		o = o + 4
	end
end

local function DecodeBC5( data, at )
	DecodeChannel( data, at, channelA )
	DecodeChannel( data, at + 8, channelB )
	local o = 1
	for k = 1, 16 do
		px[ o ], px[ o + 1 ], px[ o + 2 ], px[ o + 3 ] = channelA[ k ], channelB[ k ], 0, 255
		o = o + 4
	end
end

-- BC7 --------------------------------------------------------------------

-- subsets, partition bits, rotation bits, index-selection bit, colour bits,
-- alpha bits, p-bit per endpoint, p-bit shared per subset, index bits,
-- second index bits
local BC7_MODES = {
	[ 0 ] = { 3, 4, 0, 0, 4, 0, 1, 0, 3, 0 },
	[ 1 ] = { 2, 6, 0, 0, 6, 0, 0, 1, 3, 0 },
	[ 2 ] = { 3, 6, 0, 0, 5, 0, 0, 0, 2, 0 },
	[ 3 ] = { 2, 6, 0, 0, 7, 0, 1, 0, 2, 0 },
	[ 4 ] = { 1, 0, 2, 1, 5, 6, 0, 0, 2, 3 },
	[ 5 ] = { 1, 0, 2, 0, 7, 8, 0, 0, 2, 2 },
	[ 6 ] = { 1, 0, 0, 0, 7, 7, 1, 0, 4, 0 },
	[ 7 ] = { 2, 6, 0, 0, 5, 5, 1, 0, 2, 0 },
}

local BC7_WEIGHTS = {
	[ 2 ] = { [ 0 ] = 0, 21, 43, 64 },
	[ 3 ] = { [ 0 ] = 0, 9, 18, 27, 37, 46, 55, 64 },
	[ 4 ] = { [ 0 ] = 0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64 },
}

local function Rows( text )
	local out, index = {}, 0
	for row in string.gmatch( text, "%d+" ) do
		local t = {}
		for k = 1, #row do t[ k - 1 ] = byte( row, k ) - 48 end
		out[ index ] = t
		index = index + 1
	end
	return out
end

local function Numbers( text )
	local out, index = {}, 0
	for value in string.gmatch( text, "%d+" ) do
		out[ index ] = tonumber( value )
		index = index + 1
	end
	return out
end

local BC7_PARTITIONS2 = Rows( [[
0011001100110011 0001000100010001 0111011101110111 0001001100110111
0000000100010011 0011011101111111 0001001101111111 0000000100110111
0000000000010011 0011011111111111 0000000101111111 0000000000010111
0001011111111111 0000000011111111 0000111111111111 0000000000001111
0000100011101111 0111000100000000 0000000010001110 0111001100010000
0011000100000000 0000100011001110 0000000010001100 0111001100110001
0011000100010000 0000100010001100 0110011001100110 0011011001101100
0001011111101000 0000111111110000 0111000110001110 0011100110011100
0101010101010101 0000111100001111 0101101001011010 0011001111001100
0011110000111100 0101010110101010 0110100101101001 0101101010100101
0111001111001110 0001001111001000 0011001001001100 0011101111011100
0110100110010110 0011110011000011 0110011010011001 0000011001100000
0100111001000000 0010011100100000 0000001001110010 0000010011100100
0110110010010011 0011011011001001 0110001110011100 0011100111000110
0110110011001001 0110001100111001 0111111010000001 0001100011100111
0000111100110011 0011001111110000 0010001011101110 0100010001110111
]] )

local BC7_PARTITIONS3 = Rows( [[
0011001102212222 0001001122112221 0000200122112211 0222002200110111
0000000011221122 0011001100220022 0022002211111111 0011001122112211
0000000011112222 0000111111112222 0000111122222222 0012001200120012
0112011201120112 0122012201220122 0011011211221222 0011200122002220
0001001101121122 0111001120012200 0000112211221122 0022002200221111
0111011102220222 0001000122212221 0000001101220122 0000110022102210
0122012200110000 0012001211222222 0110122112210110 0000011012211221
0022110211020022 0110011020022222 0011012201220011 0000200022112221
0000000211221222 0222002200120011 0011001200220222 0120012001200120
0000111122220000 0120120120120120 0120201212010120 0011220011220011
0011112222000011 0101010122222222 0000000021212121 0022112200221122
0022001100220011 0220122102201221 0101222222220101 0000212121212121
0101010101012222 0222011102220111 0002111200021112 0000211221122112
0222011101110222 0002111211120002 0110011001102222 0000000021122112
0110011022222222 0022001100110022 0022112211220022 0000000000002112
0002000100020001 0222122202221222 0101222222222222 0111201122012220
]] )

local BC7_ANCHOR2 = Numbers( [[
15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15
15  2  8  2  2  8  8 15  2  8  2  2  8  8  2  2
15 15  6  8  2  8 15 15  2  8  2  2  2 15 15  6
 6  2  6  8 15 15  2  2 15 15 15 15 15  2  2 15
]] )

local BC7_ANCHOR3A = Numbers( [[
 3  3 15 15  8  3 15 15  8  8  6  6  6  5  3  3
 3  3  8 15  3  3  6 10  5  8  8  6  8  5 15 15
 8 15  3  5  6 10  8 15 15  3 15  5 15 15 15 15
 3 15  5  5  5  8  5 10  5 10  8 13 15 12  3  3
]] )

local BC7_ANCHOR3B = Numbers( [[
15  8  8  3 15 15  3  8 15 15 15 15 15 15 15  8
15  8 15  3 15  8 15  8  3 15  6 10 15 15 10  8
15  3 15 10 10  8  9 10  6 15  8 15  3  6  6  8
15  3 15 15 15 15 15 15 15 15 15 15  3 15 15  8
]] )

local POW2 = {}
for k = 0, 32 do POW2[ k ] = 2 ^ k end

local blockBytes = {}
local bitPosition = 0

local function Bits( count )
	local value, shift = 0, 0
	while count > 0 do
		local index = floor( bitPosition / 8 ) + 1
		local offset = bitPosition % 8
		local take = 8 - offset
		if take > count then take = count end
		value = value + floor( blockBytes[ index ] / POW2[ offset ] ) % POW2[ take ] * POW2[ shift ]
		shift = shift + take
		bitPosition = bitPosition + take
		count = count - take
	end
	return value
end

local endpoints = {}
for k = 0, 5 do endpoints[ k ] = {} end
local pbits, indices, indices2 = {}, {}, {}

local function Unquantize( value, bits )
	value = value * POW2[ 8 - bits ]
	return value + floor( value / POW2[ bits ] )
end

local function DecodeBC7( data, at )
	local b = blockBytes
	b[ 1 ], b[ 2 ], b[ 3 ], b[ 4 ], b[ 5 ], b[ 6 ], b[ 7 ], b[ 8 ],
	b[ 9 ], b[ 10 ], b[ 11 ], b[ 12 ], b[ 13 ], b[ 14 ], b[ 15 ], b[ 16 ] = byte( data, at, at + 15 )

	local first = b[ 1 ]
	if first == 0 then
		for k = 1, 64 do px[ k ] = 0 end
		return
	end
	local mode = 0
	while first % 2 == 0 do
		first = first / 2
		mode = mode + 1
	end
	bitPosition = mode + 1

	local spec = BC7_MODES[ mode ]
	local subsets, colourBits, alphaBits = spec[ 1 ], spec[ 5 ], spec[ 6 ]
	local indexBits, indexBits2 = spec[ 9 ], spec[ 10 ]
	local partition = spec[ 2 ] > 0 and Bits( spec[ 2 ] ) or 0
	local rotation = spec[ 3 ] > 0 and Bits( spec[ 3 ] ) or 0
	local selector = spec[ 4 ] > 0 and Bits( spec[ 4 ] ) or 0
	local ends = subsets * 2 - 1

	for channel = 1, 3 do
		for e = 0, ends do endpoints[ e ][ channel ] = Bits( colourBits ) end
	end
	if alphaBits > 0 then
		for e = 0, ends do endpoints[ e ][ 4 ] = Bits( alphaBits ) end
	end

	local hasP = spec[ 7 ] > 0 or spec[ 8 ] > 0
	if spec[ 7 ] > 0 then
		for e = 0, ends do pbits[ e ] = Bits( 1 ) end
	elseif spec[ 8 ] > 0 then
		for s = 0, subsets - 1 do
			local p = Bits( 1 )
			pbits[ s * 2 ], pbits[ s * 2 + 1 ] = p, p
		end
	end

	for e = 0, ends do
		local endpoint = endpoints[ e ]
		for channel = 1, 3 do
			local value, bits = endpoint[ channel ], colourBits
			if hasP then value, bits = value * 2 + pbits[ e ], bits + 1 end
			endpoint[ channel ] = Unquantize( value, bits )
		end
		if alphaBits > 0 then
			local value, bits = endpoint[ 4 ], alphaBits
			if hasP then value, bits = value * 2 + pbits[ e ], bits + 1 end
			endpoint[ 4 ] = Unquantize( value, bits )
		else
			endpoint[ 4 ] = 255
		end
	end

	local table2, anchorB, anchorC
	if subsets == 2 then
		table2, anchorB, anchorC = BC7_PARTITIONS2[ partition ], BC7_ANCHOR2[ partition ], -1
	elseif subsets == 3 then
		table2, anchorB, anchorC = BC7_PARTITIONS3[ partition ], BC7_ANCHOR3A[ partition ], BC7_ANCHOR3B[ partition ]
	else
		anchorB, anchorC = -1, -1
	end

	for k = 0, 15 do
		local bits = indexBits
		if k == 0 or k == anchorB or k == anchorC then bits = bits - 1 end
		indices[ k ] = Bits( bits )
	end
	if indexBits2 > 0 then
		for k = 0, 15 do indices2[ k ] = Bits( k == 0 and indexBits2 - 1 or indexBits2 ) end
	end

	local weights, weights2 = BC7_WEIGHTS[ indexBits ], BC7_WEIGHTS[ indexBits2 ]
	local o = 1
	for k = 0, 15 do
		local subset = table2 and table2[ k ] or 0
		local e0, e1 = endpoints[ subset * 2 ], endpoints[ subset * 2 + 1 ]
		local colourWeight, alphaWeight
		if indexBits2 == 0 then
			colourWeight = weights[ indices[ k ] ]
			alphaWeight = colourWeight
		elseif selector == 0 then
			colourWeight, alphaWeight = weights[ indices[ k ] ], weights2[ indices2[ k ] ]
		else
			colourWeight, alphaWeight = weights2[ indices2[ k ] ], weights[ indices[ k ] ]
		end

		local cw = 64 - colourWeight
		local r = floor( ( e0[ 1 ] * cw + e1[ 1 ] * colourWeight + 32 ) / 64 )
		local g = floor( ( e0[ 2 ] * cw + e1[ 2 ] * colourWeight + 32 ) / 64 )
		local bl = floor( ( e0[ 3 ] * cw + e1[ 3 ] * colourWeight + 32 ) / 64 )
		local a = floor( ( e0[ 4 ] * ( 64 - alphaWeight ) + e1[ 4 ] * alphaWeight + 32 ) / 64 )

		if rotation == 1 then r, a = a, r
		elseif rotation == 2 then g, a = a, g
		elseif rotation == 3 then bl, a = a, bl end

		px[ o ], px[ o + 1 ], px[ o + 2 ], px[ o + 3 ] = r, g, bl, a
		o = o + 4
	end
end

local BLOCK_DECODERS = {
	bc1 = DecodeBC1, bc2 = DecodeBC2, bc3 = DecodeBC3,
	bc4 = DecodeBC4, bc5 = DecodeBC5, bc7 = DecodeBC7,
}

-- One pixel of an uncompressed format as R, G, B, A.
local function ReadPixel( format, data, at )
	if format == "rgba8" then return byte( data, at, at + 3 ) end
	if format == "bgra8" then
		local b, g, r, a = byte( data, at, at + 3 )
		return r, g, b, a
	end
	if format == "bgrx8" then
		local b, g, r = byte( data, at, at + 2 )
		return r, g, b, 255
	end
	if format == "rgbx8" then
		local r, g, b = byte( data, at, at + 2 )
		return r, g, b, 255
	end
	if format == "bgr8" then
		local b, g, r = byte( data, at, at + 2 )
		return r, g, b, 255
	end
	if format == "r8" or format == "l8" then
		local v = byte( data, at )
		return v, v, v, 255
	end
	if format == "rg8" then
		local r, g = byte( data, at, at + 1 )
		return r, g, 0, 255
	end
	if format == "l8a8" then
		local v, a = byte( data, at, at + 1 )
		return v, v, v, a
	end
	if format == "a8" then return 255, 255, 255, byte( data, at ) end
	return 0, 0, 0, 255
end

E.DecodeBlock = function( format, data, at )
	BLOCK_DECODERS[ format ]( data, at )
	return px
end

---------------------------------------------------------------------------
-- Images out
---------------------------------------------------------------------------
-- Decoded rows go straight into a PNG with stored (uncompressed) deflate
-- blocks. A real compressor in Lua costs more than the decode itself, and
-- these files are a cache: the largest, a 2048 px RGBA stand-in, is 16 MB,
-- inside the native writer's 32 MiB read ceiling.

local CRC_TABLE

local function CRCTable()
	if CRC_TABLE then return CRC_TABLE end
	CRC_TABLE = {}
	for i = 0, 255 do
		local c = i
		for _ = 1, 8 do
			if bit.band( c, 1 ) == 1 then
				c = bit.bxor( 0xEDB88320, bit.rshift( c, 1 ) )
			else
				c = bit.rshift( c, 1 )
			end
		end
		CRC_TABLE[ i ] = c
	end
	return CRC_TABLE
end

-- util.CRC is the same CRC-32 in C on the real game, and much faster; it is
-- only trusted after it gives the standard check value.
local fastCRC
local function CRC32( text )
	if fastCRC == nil then
		fastCRC = util and isfunction( util.CRC ) and util.CRC( "123456789" ) == "3421780262" or false
	end
	if fastCRC then return tonumber( util.CRC( text ) ) end

	local t, c = CRCTable(), 0xFFFFFFFF
	for k = 1, #text do
		c = bit.bxor( t[ bit.band( bit.bxor( c, byte( text, k ) ), 0xFF ) ], bit.rshift( c, 8 ) )
	end
	c = bit.bxor( c, 0xFFFFFFFF )
	if c < 0 then c = c + 4294967296 end
	return c
end

local function BE32( n )
	return string.char( floor( n / 16777216 ) % 256, floor( n / 65536 ) % 256, floor( n / 256 ) % 256, n % 256 )
end

local function Chunk( out, kind, data )
	out[ #out + 1 ] = BE32( #data )
	out[ #out + 1 ] = kind
	out[ #out + 1 ] = data
	out[ #out + 1 ] = BE32( CRC32( kind .. data ) )
end

local IDAT_LIMIT = 1048576

local PNGWriter = {}
PNGWriter.__index = PNGWriter

local function NewPNG( width, height, colourType )
	local out = { "\137PNG\13\10\26\10" }
	Chunk( out, "IHDR", BE32( width ) .. BE32( height ) .. string.char( 8, colourType, 0, 0, 0 ) )
	return setmetatable( {
		out = out, pending = {}, pendingBytes = 0, idat = { "\120\1" }, idatBytes = 2,
		a = 1, b = 0,
	}, PNGWriter )
end

function PNGWriter:Stored( data, final )
	local length = #data
	local block = string.char( final and 1 or 0, length % 256, floor( length / 256 ),
		( 65535 - length ) % 256, floor( ( 65535 - length ) / 256 ) ) .. data
	self.idat[ #self.idat + 1 ] = block
	self.idatBytes = self.idatBytes + #block
	if self.idatBytes >= IDAT_LIMIT then
		Chunk( self.out, "IDAT", concat( self.idat ) )
		self.idat, self.idatBytes = {}, 0
	end
end

--- One finished row, as a string of bytes without its filter byte.
function PNGWriter:Row( row )
	local data = "\0" .. row
	local a, b = self.a, self.b
	local length = #data
	local at = 1
	while at <= length do
		local stop = min( length, at + 65535 )
		for k = at, stop do
			a = a + byte( data, k )
			b = b + a
		end
		a, b = a % 65521, b % 65521
		at = stop + 1
	end
	self.a, self.b = a, b

	self.pending[ #self.pending + 1 ] = data
	self.pendingBytes = self.pendingBytes + length
	while self.pendingBytes >= 65535 do
		local joined = concat( self.pending )
		self:Stored( sub( joined, 1, 65535 ), false )
		local rest = sub( joined, 65536 )
		self.pending, self.pendingBytes = { rest }, #rest
	end
end

function PNGWriter:Finish()
	self:Stored( concat( self.pending ), true )
	self.idat[ #self.idat + 1 ] = BE32( self.b * 65536 + self.a )
	Chunk( self.out, "IDAT", concat( self.idat ) )
	Chunk( self.out, "IEND", "" )
	return concat( self.out )
end

E.NewPNG = NewPNG

-- The colour type and per-pixel bytes for a map role. Single-channel maps go
-- out as grey; a two-channel normal map gets a blue channel so the writer's
-- mip chain renormalises it gently instead of flattening it.
local GREY_ROLES = {
	roughness = true, metallic = true, height = true, anisotropy = true, subsurface_thickness = true,
}

local function Layout( info, role, purpose )
	if GREY_ROLES[ role ] then return 0, 1 end
	if role == "normal" then return 2, 3 end
	if purpose == "thumb" or not info.alpha then return 2, 3 end
	return 6, 4
end

local CHAR_LIMIT = 4096

local function RowString( row, count )
	if count <= CHAR_LIMIT then return string.char( unpack( row, 1, count ) ) end
	local parts = {}
	for first = 1, count, CHAR_LIMIT do
		parts[ #parts + 1 ] = string.char( unpack( row, first, min( count, first + CHAR_LIMIT - 1 ) ) )
	end
	return concat( parts )
end

-- Mean of each 2x2 group of pixels, for files with no small enough mip.
local function Halve( rows, width, height, channels )
	local w, h = max( 1, floor( width / 2 ) ), max( 1, floor( height / 2 ) )
	local out = {}
	for y = 0, h - 1 do
		local top = rows[ min( height - 1, y * 2 ) ]
		local bottom = rows[ min( height - 1, y * 2 + 1 ) ]
		local row = {}
		for x = 0, w - 1 do
			local left = min( width - 1, x * 2 ) * channels
			local right = min( width - 1, x * 2 + 1 ) * channels
			for c = 1, channels do
				row[ x * channels + c ] = floor( ( top[ left + c ] + top[ right + c ]
					+ bottom[ left + c ] + bottom[ right + c ] ) / 4 + 0.5 )
			end
		end
		out[ y ] = row
	end
	return out, w, h
end

-- Lua 5.1 says nil on the main thread; 5.2 and later say (thread, true).
local function Yield( budget )
	local thread, main = coroutine.running()
	if thread and not main and budget and Clock() > budget.until_ then
		coroutine.yield()
	end
end

--- Decode one level of a DDS file into a PNG. Returns the PNG bytes, width
--- and height, or nil plus a reason. Inside a coroutine it pauses whenever
--- `budget.until_` has passed.
function E.DecodeToPNG( path, info, levelIndex, halvings, role, purpose, budget )
	local level = info.levels[ levelIndex ]
	if not level then return nil, "missing mip level" end

	local data = FS.ReadRange( path, level.offset, level.size )
	if not isstring( data ) or #data < level.size then return nil, "could not read the mip level" end

	local spec = FORMATS[ info.format ]
	local width, height = level.width, level.height
	local colourType, channels = Layout( info, role, purpose )
	local twoChannel = info.channels == 2 and role == "normal"
	local rows = {}
	for y = 0, height - 1 do rows[ y ] = {} end

	local function Store( row, x, r, g, b, a )
		local o = x * channels
		if channels == 1 then
			row[ o + 1 ] = r
		else
			if twoChannel then
				local nx, ny = r / 127.5 - 1, g / 127.5 - 1
				local nz = 1 - nx * nx - ny * ny
				b = floor( ( ( nz > 0 and math.sqrt( nz ) or 0 ) * 0.5 + 0.5 ) * 255 + 0.5 )
			end
			row[ o + 1 ], row[ o + 2 ], row[ o + 3 ] = r, g, b
			if channels == 4 then row[ o + 4 ] = a end
		end
	end

	if spec.block then
		local decode = BLOCK_DECODERS[ info.format ]
		local blocksWide = max( 1, floor( ( width + 3 ) / 4 ) )
		local blocksHigh = max( 1, floor( ( height + 3 ) / 4 ) )
		local at = 1
		for by = 0, blocksHigh - 1 do
			for bx = 0, blocksWide - 1 do
				decode( data, at )
				at = at + spec.block
				local o = 1
				for r = 0, 3 do
					local y = by * 4 + r
					local row = rows[ y ]
					for c = 0, 3 do
						local x = bx * 4 + c
						if row and x < width then
							Store( row, x, px[ o ], px[ o + 1 ], px[ o + 2 ], px[ o + 3 ] )
						end
						o = o + 4
					end
				end
			end
			Yield( budget )
		end
	else
		local bpp, at = spec.bpp, 1
		for y = 0, height - 1 do
			local row = rows[ y ]
			for x = 0, width - 1 do
				Store( row, x, ReadPixel( info.format, data, at ) )
				at = at + bpp
			end
			Yield( budget )
		end
	end
	data = nil

	for _ = 1, halvings do
		if width == 1 and height == 1 then break end
		rows, width, height = Halve( rows, width, height, channels )
		Yield( budget )
	end

	local png = NewPNG( width, height, colourType )
	local count = width * channels
	for y = 0, height - 1 do
		png:Row( RowString( rows[ y ], count ) )
		rows[ y ] = nil
		Yield( budget )
	end
	return png:Finish(), width, height
end

---------------------------------------------------------------------------
-- The image queue
---------------------------------------------------------------------------

local swept = false

-- Delete cache files nobody has written for a month. Each one can be decoded
-- again from its DDS, so this never loses anything.
local function Sweep()
	if swept or not file or not isfunction( file.Find ) then return end
	swept = true
	local now = os.time()
	local names = file.Find( IMAGE_DIR .. "/*.png", "DATA" ) or {}
	for _, name in ipairs( names ) do
		local path = IMAGE_DIR .. "/" .. name
		local written = file.Time( path, "DATA" ) or now
		if now - written > CACHE_DAYS * 86400 then pcall( file.Delete, path ) end
	end
end

local function EnsureFolder()
	if not file.IsDir( "advmat", "DATA" ) then file.CreateDir( "advmat" ) end
	if not file.IsDir( IMAGE_DIR, "DATA" ) then file.CreateDir( IMAGE_DIR ) end
end

-- What one request decodes, and the file it lands in. The name changes with
-- the DDS file's size and time, so a regenerated map is never served stale.
local function Plan( path, purpose, role, limits )
	local info, err = E.DDSInfo( path )
	if not info then return nil, err end

	local side, maxBytes
	if purpose == "thumb" then
		side = THUMB_SIDE
	elseif purpose == "edit" then
		local gen = AdvMat.Gen
		side = gen and isfunction( gen.MaxSize ) and gen.MaxSize() or 1024
	else
		-- A stand-in is a picture the writer decodes, so the decode limits
		-- apply, not the larger ones a later bridge copies a DDS up to.
		limits = limits or {}
		side = tonumber( limits.maxDecodedTextureDimension ) or tonumber( limits.maxTextureDimension ) or 2048
		maxBytes = tonumber( limits.maxDecodedTextureBytes ) or tonumber( limits.maxTextureBytes )
	end

	local levelIndex, halvings = PickLevel( info, side, maxBytes )
	local level = info.levels[ levelIndex ]
	local w, h = level.width, level.height
	for _ = 1, halvings do w, h = max( 1, floor( w / 2 ) ), max( 1, floor( h / 2 ) ) end
	local colourType = Layout( info, role, purpose )

	local key = table.concat( {
		string.lower( path ), info.stamp, levelIndex, halvings, colourType, tostring( role ), purpose,
	}, "|" )
	local digest = string.sub( AdvMat.SHA1( key ), 1, 20 )
	return {
		path = path, purpose = purpose, role = role, info = info,
		level = levelIndex, halvings = halvings, width = w, height = h,
		key = key, output = IMAGE_DIR .. "/" .. purpose .. "_" .. digest .. ".png",
	}
end

local worker

local function Finish( job, output, reason )
	local waiting = E.ImageWait[ job.key ]
	E.ImageWait[ job.key ] = nil
	if output then
		E.ImageReady[ job.key ] = output
		E.ImageFailed[ job.key ] = nil
	else
		E.ImageFailed[ job.key ] = { at = Clock(), reason = reason }
		AdvMat.Log( "Could not decode %s: %s", job.path, tostring( reason ) )
	end
	for _, done in ipairs( waiting and waiting.callbacks or {} ) do
		local ok, err = pcall( done, output, reason )
		if not ok then AdvMat.Log( "Enhancement image callback failed: %s", tostring( err ) ) end
	end
	hook.Run( "AdvMatRTXEnhancementImage", job.path, output, reason )
end

local function Run( job, budget )
	local png, reason = E.DecodeToPNG( job.path, job.info, job.level, job.halvings, job.role, job.purpose, budget )
	if not png then return nil, reason end

	if job.purpose == "edit" then
		local import = AdvMat.Import
		if not import or not isfunction( import.StoreDecoded ) then
			return nil, "the import store is unavailable"
		end
		return import.StoreDecoded( png, E.Describe( job.path ) )
	end

	EnsureFolder()
	file.Write( job.output, png )
	if file.Read( job.output, "DATA" ) ~= png then
		pcall( file.Delete, job.output )
		return nil, "could not write data/" .. job.output
	end
	return "data/" .. job.output
end

-- One job at a time, resumed once a frame. Only the first resume hands the
-- coroutine its job; the budget table it was given is refreshed in place so
-- the decoder's pause checks see each new frame's deadline.
local function PumpImages()
	if not worker then
		local job = table.remove( E.ImageQueue, 1 )
		if not job then
			hook.Remove( "Think", "AdvMat.RTXEnhanceImages" )
			return
		end
		worker = { job = job, thread = coroutine.create( Run ), budget = {}, started = false }
	end

	worker.budget.until_ = Clock() + FRAME_BUDGET
	local ok, output, reason
	if worker.started then
		ok, output, reason = coroutine.resume( worker.thread )
	else
		worker.started = true
		ok, output, reason = coroutine.resume( worker.thread, worker.job, worker.budget )
	end
	if ok and coroutine.status( worker.thread ) ~= "dead" then return end

	local job = worker.job
	worker = nil
	if not ok then Finish( job, nil, tostring( output ) ) return end
	Finish( job, output, reason )
end

E.PumpImages = PumpImages

--- Decode `path` for `purpose` ("thumb", "edit" or "carry"). Returns the
--- finished path at once when it already exists; otherwise queues the work,
--- returns nil, and calls `done( path | nil, reason )` when it lands.
---
--- thumb and carry paths are "data/advmat/remix/...png"; edit returns an
--- import path, "data/advmat/imports/img_<hash>.png".
function E.RequestImage( path, purpose, role, limits, done )
	local job, err = Plan( path, purpose, role, limits )
	if not job then
		if done then done( nil, err ) end
		return nil, err
	end

	local ready = E.ImageReady[ job.key ]
	if ready then
		local still
		if job.purpose == "edit" then
			still = AdvMat.Import and isfunction( AdvMat.Import.Has ) and AdvMat.Import.Has( ready )
		else
			still = file.Exists( string.sub( ready, 6 ), "DATA" )
		end
		if still then
			if done then done( ready ) end
			return ready
		end
		E.ImageReady[ job.key ] = nil
	end
	if job.purpose ~= "edit" and file.Exists( job.output, "DATA" ) then
		E.ImageReady[ job.key ] = "data/" .. job.output
		if done then done( "data/" .. job.output ) end
		return "data/" .. job.output
	end

	local failed = E.ImageFailed[ job.key ]
	if failed and Clock() - failed.at < 10 then
		if done then done( nil, failed.reason ) end
		return nil, failed.reason
	end

	Sweep()
	local waiting = E.ImageWait[ job.key ]
	if waiting then
		if done then waiting.callbacks[ #waiting.callbacks + 1 ] = done end
		return nil
	end

	E.ImageWait[ job.key ] = { job = job, callbacks = { done } }
	-- Previews jump the queue: they are small and the person is looking at them.
	if purpose == "thumb" then
		table.insert( E.ImageQueue, 1, job )
	else
		E.ImageQueue[ #E.ImageQueue + 1 ] = job
	end
	hook.Add( "Think", "AdvMat.RTXEnhanceImages", PumpImages )
	return nil
end

-- Paint asks for a row's preview every frame; ask the file system at most a
-- few times a second while one is being decoded.
local THUMB_RECHECK = 0.25

--- The preview material for a map row, or nil while it is being decoded.
function E.ThumbnailMaterial( path, role )
	local memoKey = tostring( path ) .. "|" .. tostring( role )
	local memo = E.Thumbs[ memoKey ]
	if memo and memo.material ~= nil then return memo.material or nil end
	if memo and Clock() - memo.at < THUMB_RECHECK then return nil end
	memo = { at = Clock() }
	E.Thumbs[ memoKey ] = memo

	local ready = E.RequestImage( path, "thumb", role )
	if not ready then return nil end

	local ok, material = pcall( Material, ready, "noclamp smooth" )
	memo.material = ok and material and not material:IsError() and material or false
	return memo.material or nil
end

---------------------------------------------------------------------------
-- What the native writer can take
---------------------------------------------------------------------------

--- Whether the installed writer would refuse this enhancement texture as it
--- is, so a decoded stand-in has to go in its place. `limits` is the native
--- capability table's maxTextureDimension / maxTextureBytes.
function E.NeedsCarry( path, ops, limits )
	if not E.IsModTexture( path ) then return false end
	if istable( ops ) and #ops > 0 then return true end
	if E.LinkedMods[ E.ModOf( path ) ] then return true end

	local info = E.DDSInfo( path )
	if not info then return false end
	local maxDimension = limits and tonumber( limits.maxTextureDimension ) or 2048
	local maxBytes = limits and tonumber( limits.maxTextureBytes ) or 33554432
	return info.width > maxDimension or info.height > maxDimension or ( info.fileSize or 0 ) > maxBytes
end

--- After the writer refused a profile because a texture's real path left the
--- game folder, remember every enhancement mod that profile named directly.
--- Returns whether anything new was learned (and a retry can succeed).
function E.NoteLinkedRefusal( compiled, reason )
	if not isstring( reason ) or not find( reason, "texture_path_outside_allowed_roots", 1, true ) then
		return false
	end
	local learned = false
	for _, map in pairs( compiled and compiled.pbr and compiled.pbr.maps or {} ) do
		local source = isstring( map ) and map or ( istable( map ) and not map.generatedFile and map.source )
		local folder = E.ModOf( source )
		if folder and not E.LinkedMods[ folder ] then
			E.LinkedMods[ folder ] = true
			learned = true
			AdvMat.Log( "RTX enhancement mod %s is linked from outside the game folder; its maps are carried as decoded copies.", folder )
		end
	end
	return learned
end

---------------------------------------------------------------------------
-- Console report
---------------------------------------------------------------------------
-- advmat_rtx_enhancements                 every mod, in the runtime's order
-- advmat_rtx_enhancements <hash|material> what replaces it, and what AME reads

if CLIENT then
	concommand.Add( "advmat_rtx_enhancements", function( _, _, args )
		E.Refresh( true )
		local query = args[ 1 ]

		if not query then
			AdvMat.Log( "%d Remix mod(s) read in %d ms:", #E.Mods, E.LastScanMS or 0 )
			for rank, record in ipairs( E.Mods ) do
				AdvMat.Log( "  %2d. %-40s %5d material(s), %d layer(s)%s", rank, record.folder, record.count or 0,
					#( record.stack or {} ), #( record.errors or {} ) > 0
						and ( "  [" .. concat( record.errors, "; " ) .. "]" ) or "" )
			end
			return
		end

		local hashes = { query }
		if not NormalizeHash( query ) and AdvMat.RTX.Bridge and AdvMat.RTX.Bridge.ResolveHashes then
			hashes = AdvMat.RTX.Bridge.ResolveHashes( query )
		end
		local result = E.Lookup( hashes )
		AdvMat.Log( "%s: hash(es) %s", query, #result.hashes > 0 and concat( result.hashes, ", " ) or "none captured" )
		if #result.entries == 0 then AdvMat.Log( "  no mod replaces it" ) end
		for index, entry in ipairs( result.entries ) do
			AdvMat.Log( "  %d. %s  %s  (%s, %s)%s", index, entry.folder, E.LayerName( entry.material ), entry.material.kind,
				entry.material.shaderAsset or "no MDL named", entry == result.effective and "  <- drawn" or "" )
		end

		local base = result.enhancement
		if base then
			local pbr, notes = E.Seed( base.material )
			for key, map in SortedPairs( pbr.maps ) do
				local info = E.DDSInfo( map )
				AdvMat.Log( "    map %-24s %s  %s", key, map,
					info and ( info.width .. "x" .. info.height .. " " .. info.format ) or "?" )
			end
			for key, value in SortedPairs( pbr.constants ) do
				AdvMat.Log( "    %-28s %s", key, istable( value )
					and string.format( "(%g, %g, %g)", value.r, value.g, value.b ) or tostring( value ) )
			end
			if #notes.unsupported > 0 then AdvMat.Log( "    not carried: %s", concat( notes.unsupported, ", " ) ) end
			if #notes.clamped > 0 then AdvMat.Log( "    clamped: %s", concat( notes.clamped, ", " ) ) end
			if #notes.missing > 0 then AdvMat.Log( "    missing files: %s", concat( notes.missing, ", " ) ) end
		end
	end )
end
