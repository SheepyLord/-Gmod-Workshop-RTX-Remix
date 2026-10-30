--[[---------------------------------------------------------------------------
	Advanced Material Editor - .vmt text parser

	IMaterial:GetKeyValues() is convenient but lossy: it hands back engine
	internal flag bitfields, turns textures into ITexture objects and turns
	texture transforms into VMatrix objects that cannot be converted back into
	the "center .5 .5 scale 1 1 rotate 0 translate 0 0" text a VMT needs.

	Reading the .vmt itself avoids all of that. The GAME search path covers
	loose files, VPKs and mounted .gma addons, so this works for workshop
	content too. GetKeyValues stays as the fallback for materials that have no
	.vmt on disk (procedural materials, engine render targets).
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local MAX_INCLUDE_DEPTH = 4

---------------------------------------------------------------------------
-- Tokeniser
---------------------------------------------------------------------------
local function Tokenise( text )
	local tokens = {}
	local i, n   = 1, #text

	while i <= n do
		local c = string.sub( text, i, i )

		if c == "\"" then
			----------------------------------------------------- quoted
			local close = string.find( text, "\"", i + 1, true )
			if not close then break end
			tokens[ #tokens + 1 ] = string.sub( text, i + 1, close - 1 )
			i = close + 1

		elseif c == "/" and string.sub( text, i + 1, i + 1 ) == "/" then
			---------------------------------------------------- comment
			local nl = string.find( text, "\n", i, true )
			i = nl and ( nl + 1 ) or ( n + 1 )

		elseif c == "{" or c == "}" then
			----------------------------------------------------- braces
			tokens[ #tokens + 1 ] = c
			i = i + 1

		elseif c == "[" then
			------------------------------------------- dx conditional
			-- e.g. "$bumpmap" "x" [$LOWENDDX8]  -- the suffix is ignored,
			-- but "[1 0 0]" vectors are values and must be kept.
			local close = string.find( text, "]", i, true )
			if not close then break end

			local body = string.sub( text, i, close )
			if string.find( body, "^%[%s*[-%d%.]" ) then
				tokens[ #tokens + 1 ] = body
			end
			i = close + 1

		elseif string.find( c, "%s" ) then
			i = i + 1

		else
			------------------------------------------------------ bare
			local stop = string.find( text, "[%s{}\"]", i ) or ( n + 1 )
			tokens[ #tokens + 1 ] = string.sub( text, i, stop - 1 )
			i = stop
		end
	end

	return tokens
end

---------------------------------------------------------------------------
-- Block parser
---------------------------------------------------------------------------
local MERGE_BLOCKS = { insert = true, replace = true }

--- Read one { ... } block starting at tokens[i] == "{". Returns the key
--- values it contains and the index just past the closing brace.
local function ParseBlock( tokens, i, out, depth )
	out   = out or {}
	depth = depth or 0

	i = i + 1 -- step over "{"

	while i <= #tokens do
		local tok = tokens[ i ]

		if tok == "}" then return out, i + 1 end

		local nxt = tokens[ i + 1 ]

		if nxt == "{" then
			------------------------------------------------- sub block
			local lower = string.lower( tok )

			if MERGE_BLOCKS[ lower ] then
				-- Patch insert / replace: fold straight into the result.
				_, i = ParseBlock( tokens, i + 1, out, depth )
			else
				-- Proxies and friends are not editable here; skip them.
				local skip = {}
				_, i = ParseBlock( tokens, i + 1, skip, depth )
			end

		elseif nxt ~= nil then
			----------------------------------------------- key / value
			local key = string.lower( tok )
			local value = nxt
			local consumed = 1

			-- "?$bumpmap" style dx-level prefixes.
			key = string.gsub( key, "^%?", "" )

			-- Valve's own materials sometimes leave vectors unquoted and
			-- unbracketed, for example:
			--
			--     "$envmaptint" .7 .7 .7
			--
			-- A plain key/value parser used to keep only the first .7 and then
			-- consume the remaining pair as junk.  CreateMaterial consequently
			-- created a STRING material var where the shader requires a vector;
			-- every draw then emitted CMaterialVar::GetVecValue warnings and the
			-- reflection tint was visibly corrupt.  Consecutive numeric tokens
			-- belong to the current value until the next material key or brace.
			if ( string.sub( key, 1, 1 ) == "$" or string.sub( key, 1, 1 ) == "%" )
			and tonumber( nxt ) ~= nil then
				local numbers = { nxt }
				local j = i + 2

				while #numbers < 4 and tonumber( tokens[ j ] ) ~= nil do
					numbers[ #numbers + 1 ] = tokens[ j ]
					j = j + 1
				end

				if #numbers > 1 then
					value = "[" .. table.concat( numbers, " " ) .. "]"
					consumed = #numbers
				end
			end

			if key == "include" then
				out[ "\1include" ] = value
			elseif string.sub( key, 1, 1 ) == "$" or string.sub( key, 1, 1 ) == "%" then
				out[ key ] = value
			end

			i = i + 1 + consumed
		else
			return out, i + 1
		end
	end

	return out, i
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

--- AdvMat.ParseVMT( "models/foo/bar" ) -> keyValues, shaderName
--- Follows Patch/include chains. Returns nil when the file cannot be read.
function AdvMat.ParseVMT( path, depth )
	depth = depth or 0
	path  = AdvMat.NormalizeMaterial( path )
	if path == "" or depth > MAX_INCLUDE_DEPTH then return nil end

	local raw = file.Read( "materials/" .. path .. ".vmt", "GAME" )
	if not raw or raw == "" then return nil end

	local tokens = Tokenise( raw )
	if #tokens < 2 then return nil end

	-- The shader name is whatever token sits immediately before the opening
	-- brace, which tolerates stray tokens at the top of malformed VMTs.
	local open = 1
	while open <= #tokens and tokens[ open ] ~= "{" do open = open + 1 end

	if open < 2 or tokens[ open ] ~= "{" then return nil end

	local shader = tokens[ open - 1 ]

	local kv = ( ParseBlock( tokens, open, {}, depth ) )

	------------------------------------------------------------- Patch
	local include = kv[ "\1include" ]
	kv[ "\1include" ] = nil

	if include then
		local parentKV, parentShader = AdvMat.ParseVMT( include, depth + 1 )
		if parentKV then
			for k, v in pairs( kv ) do parentKV[ k ] = v end
			return parentKV, parentShader or shader
		end
	end

	if string.lower( shader ) == "patch" then
		-- A Patch whose include could not be resolved tells us nothing useful
		-- about the real shader.
		return kv, nil
	end

	return kv, shader
end

--- True if a .vmt actually exists on any mounted search path.
function AdvMat.VMTExists( path )
	path = AdvMat.NormalizeMaterial( path )
	if path == "" then return false end
	return file.Exists( "materials/" .. path .. ".vmt", "GAME" )
end
