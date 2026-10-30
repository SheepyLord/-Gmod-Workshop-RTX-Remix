--[[---------------------------------------------------------------------------
	Advanced Material Editor - importing an image from the player's computer

	Garry's Mod Lua can only read the game's own folders. Model Hotloader's
	binary module (2.3.0 and later) publishes mmdhl.FileAccess, through which
	another client addon can read a file the player chooses in a window Lua
	cannot click; the addon receives that file and nothing else. This file is
	the only one that talks to it, and it feature-detects everything, because
	the Hotloader's Workshop addon and its native module update separately and
	players mix them.

	An imported image is not a new kind of texture. Its bytes are kept under
	data/advmat/imports/, named by their content, and the parameter receives an
	ordinary edit recipe whose source is that file and which has no steps yet
	(`sourcecopy`). Everything after that already exists: the edit builder
	draws it at the recipe's size, the asset transport hands the finished PNG
	to the server and to every other player, and Edit reopens it in the texture
	editor. Only the player who imported it ever needs the original file.

	Without the API - no Model Hotloader, its native module missing or too old,
	file access switched off, somebody else's server - no row offers Import,
	and the parameter list carries one small notice whose Resolve button says
	what is wrong and where to get the module.
-----------------------------------------------------------------------------]]

AdvMat        = AdvMat or {}
AdvMat.Import = AdvMat.Import or {}

local IMP = AdvMat.Import
local T   = AdvMat.Theme

-- Model Hotloader keys an "always allow this folder" answer by the name an
-- addon reports, so this must never be translated or reworded: a new name
-- would quietly forget every folder the player has already allowed.
local ADDON = "Advanced Material Editor"

local WORKSHOP_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id=3810025467"
local GITHUB_URL   = "https://github.com/SheepyLord/Gmod-Model-Hotloader-with-Vulkan"

local DIR        = "advmat/imports"
local NAMES_FILE = DIR .. "/names.json"

-- FileAccess.Read hands back at most 16 MiB per call.
local READ_CHUNK = 16 * 1024 * 1024

-- An uncompressed 4096 x 4096 RGBA image is 64 MiB. Nothing this editor can
-- make needs a bigger file, and the whole of it is held as one Lua string.
local MAX_BYTES = 64 * 1024 * 1024

-- The largest recipe is 4096, and the engine decodes the whole image into one
-- texture first - which Global.Material then keeps for the rest of the
-- session. An 8192 image is a quarter of a gigabyte of video memory for detail
-- no recipe can hold, so it has to be scaled down before it is imported.
local MAX_SIDE = 4096

-- How long a status answer is reused. Every texture row asks while a list is
-- built, and Model Hotloader announces the changes that matter anyway.
local STATUS_SECONDS = 5

---------------------------------------------------------------------------
-- Where imported images live
---------------------------------------------------------------------------

--- Whether `path` names an imported image. Only the exact shape this file
--- writes counts, so nothing else in a data folder is ever sampled as a
--- texture source because a recipe happened to name it.
function IMP.IsSource( path )
	if not isstring( path ) or #path > 96 then return false end

	return string.match( path, "^data/advmat/imports/img_%x+%.png$" ) ~= nil
		or string.match( path, "^data/advmat/imports/img_%x+%.jpg$" ) ~= nil
end

-- The same file relative to garrysmod/data, which is what file.* takes.
local function DataPath( path ) return string.sub( path, 6 ) end

--- Whether this computer has an imported image's file, which is true only on
--- the one it was imported on. Everywhere else the finished texture has to
--- come from the server (AdvMat.Assets.AwaitServerCopy).
function IMP.Has( path )
	return IMP.IsSource( path ) and file.Exists( DataPath( path ), "DATA" ) or false
end

local function EnsureDir()
	if not file.IsDir( "advmat", "DATA" ) then file.CreateDir( "advmat" ) end
	if not file.IsDir( DIR, "DATA" ) then file.CreateDir( DIR ) end
end

---------------------------------------------------------------------------
-- Reading an image header
---------------------------------------------------------------------------
-- The engine does the real decoding. These only turn away what it cannot
-- use, and answer what the editor needs to know before any pixel exists: how
-- big the image is, and whether it carries alpha.

local function U16( data, at )
	local a, b = string.byte( data, at, at + 1 )
	if not b then return nil end
	return a * 256 + b
end

local function U32( data, at )
	local a, b, c, d = string.byte( data, at, at + 3 )
	if not d then return nil end
	return ( ( a * 256 + b ) * 256 + c ) * 256 + d
end

local function InspectPNG( data )
	if string.sub( data, 13, 16 ) ~= "IHDR" then return nil end

	local colour = string.byte( data, 26 )
	if not colour then return nil end

	-- Grey with alpha and RGBA carry it in every pixel. A palette, or a single
	-- colour keyed out, carries it in a tRNS chunk, which the format places
	-- before the first IDAT - so the header is enough to find it.
	local alpha = colour == 4 or colour == 6
	local pos = 9

	for _ = 1, 256 do
		if alpha then break end

		local length = U32( data, pos )
		local kind   = string.sub( data, pos + 4, pos + 7 )
		if not length or #kind < 4 or kind == "IDAT" or kind == "IEND" then break end
		if kind == "tRNS" then alpha = true end

		pos = pos + 12 + length
	end

	return { format = "png", w = U32( data, 17 ), h = U32( data, 21 ), alpha = alpha }
end

-- Every marker in this range starts a frame and carries its size, apart from
-- the three that mean something else: DHT, JPG and DAC.
local NOT_FRAME = { [ 0xC4 ] = true, [ 0xC8 ] = true, [ 0xCC ] = true }

local function InspectJPEG( data )
	local pos = 3

	for _ = 1, 4096 do
		local mark, kind = string.byte( data, pos, pos + 1 )
		if mark ~= 0xFF or not kind then return nil end

		if kind == 0xFF then
			pos = pos + 1   -- a fill byte in front of the next marker
		elseif kind == 0x01 or ( kind >= 0xD0 and kind <= 0xD7 ) then
			pos = pos + 2   -- the markers that have no length
		elseif kind == 0xD9 or kind == 0xDA then
			return nil      -- the image ended, or its data began, without a frame
		elseif kind >= 0xC0 and kind <= 0xCF and not NOT_FRAME[ kind ] then
			return { format = "jpg", w = U16( data, pos + 7 ), h = U16( data, pos + 5 ), alpha = false }
		else
			local length = U16( data, pos + 2 )
			if not length or length < 2 then return nil end
			pos = pos + 2 + length
		end
	end

	return nil
end

--- Format ("png" or "jpg"), size and transparency, or nil for anything the
--- engine cannot load as an image.
local function Inspect( data )
	if not isstring( data ) then return nil end

	local info
	if string.sub( data, 1, 8 ) == "\137PNG\13\10\26\10" then
		info = InspectPNG( data )
	elseif string.sub( data, 1, 3 ) == "\255\216\255" then
		info = InspectJPEG( data )
	end

	if not info or not info.w or not info.h or info.w < 1 or info.h < 1 then return nil end
	return info
end

--- Whether an imported image carries an alpha channel; nil when its file is
--- not on this computer.
---
--- Read from the whole file, exactly as the import read it when it chose the
--- recipe's alpha handling: a tRNS chunk can sit behind any amount of metadata,
--- and the recipe and the texture reader must not disagree about it. The
--- answer is cached by GEN.SourceHasAlpha, so this happens once a session.
function IMP.HasAlpha( path )
	if not IMP.IsSource( path ) then return nil end

	local info = Inspect( file.Read( DataPath( path ), "DATA" ) )
	if not info then return nil end
	return info.alpha
end

---------------------------------------------------------------------------
-- The engine's copy
---------------------------------------------------------------------------

-- [path] = { mat, tex } once loaded, false once the engine refused it.
-- Holding the material keeps its texture loaded for every sampler naming it.
local loaded = {}

--- The engine's material and texture for an imported image, or nil.
---
--- A file that is not on this computer - an image another player imported -
--- is never handed to Global.Material. An error material for a missing file
--- can be cached under the very name a later import of the same bytes needs.
function IMP.Material( path )
	if not IMP.IsSource( path ) then return nil end

	local hit = loaded[ path ]
	if hit then return hit.mat, hit.tex end
	if hit == false then return nil end

	if not file.Exists( DataPath( path ), "DATA" ) then return nil end

	-- With mipmaps: an imported picture is usually bigger than the recipe it
	-- feeds (the default ceiling is 1024), and a photograph scaled down from its
	-- top level alone aliases. A mounted VTF carries its mips already.
	local mat = Material( path, "noclamp smooth mips" )
	local tex = mat and not mat:IsError() and mat:GetTexture( "$basetexture" ) or nil

	if not tex or ( tex.IsError and tex:IsError() ) then
		loaded[ path ] = false
		return nil
	end

	loaded[ path ] = { mat = mat, tex = tex }
	return mat, tex
end

---------------------------------------------------------------------------
-- What the player called them
---------------------------------------------------------------------------
-- A recipe carries only the content-derived path. The name of the file an
-- image came from stays on the computer that imported it, where it makes the
-- rows and the texture editor readable.

local names

local function Names()
	if names then return names end
	names = {}

	local raw = file.Read( NAMES_FILE, "DATA" )
	local stored = isstring( raw ) and util.JSONToTable( raw ) or nil

	for path, name in pairs( istable( stored ) and stored or {} ) do
		if IMP.IsSource( path ) and isstring( name ) and name ~= "" then
			names[ path ] = name
		end
	end

	return names
end

--- `text` cut to at most `limit` bytes without splitting a UTF-8 character.
local function Clip( text, limit )
	if #text <= limit then return text end

	local cut = limit
	while cut > 0 do
		local byte = string.byte( text, cut + 1 )
		if not byte or byte < 0x80 or byte >= 0xC0 then break end
		cut = cut - 1
	end

	return string.sub( text, 1, cut )
end

local function Remember( path, name )
	if not isstring( name ) then return end

	name = Clip( string.Trim( ( string.gsub( name, "%c", " " ) ) ), 120 )
	if name == "" then return end

	local known = Names()
	if known[ path ] == name then return end

	known[ path ] = name
	EnsureDir()
	file.Write( NAMES_FILE, util.TableToJSON( known ) )
end

--- The name of the file an imported image came from, when this computer
--- imported it.
function IMP.Name( path )
	return IMP.IsSource( path ) and Names()[ path ] or nil
end

--- How a row names an imported image as the source of its texture.
function IMP.Describe( path )
	local name = IMP.Name( path )
	if name then return AdvMat.L( "import.source_named", { name = name } ) end
	return AdvMat.L( "import.source" )
end

---------------------------------------------------------------------------
-- Storing an import
---------------------------------------------------------------------------

--- Name the bytes by their content. Only this computer ever derives the name,
--- so any strong hash the engine has will do, and one missing on this branch
--- costs a duplicate file, nothing more. The pure-Lua SHA-1 in sh_10_util is
--- never used here: a 30 MB photograph would freeze the game for it.
local function Digest( data )
	for _, name in ipairs( { "SHA256", "SHA1", "MD5" } ) do
		local fn = util[ name ]

		if isfunction( fn ) then
			local ok, digest = pcall( fn, data )
			digest = ok and isstring( digest ) and string.lower( digest ) or ""

			if #digest >= 32 and not string.find( digest, "[^%x]" ) then
				return string.sub( digest, 1, 40 )
			end
		end
	end

	return string.format( "%08x%08x", tonumber( util.CRC( data ) ) or 0, #data % 4294967296 )
end

local function Store( data, info )
	local path   = "data/" .. DIR .. "/img_" .. Digest( data ) .. "." .. info.format
	local target = DataPath( path )

	-- Named by content, so a file already there is already these bytes -
	-- unless an earlier write was cut short, which the comparison catches.
	if file.Read( target, "DATA" ) ~= data then
		EnsureDir()
		file.Write( target, data )

		if file.Read( target, "DATA" ) ~= data then
			pcall( file.Delete, target )
			return nil, AdvMat.L( "import.error_write" )
		end
	end

	return path
end

--- Keep an image this addon decoded itself - an RTX Remix enhancement map
--- about to be opened in the texture editor - as an import named `name`.
--- From here on it is exactly a picture from this computer: the edit made
--- from it reaches other players through the server, as any import does.
--- Returns the import path, or nil plus the reason.
function IMP.StoreDecoded( data, name )
	local info = Inspect( data )
	if not info then return nil, AdvMat.L( "import.error_format" ) end
	if info.w > MAX_SIDE or info.h > MAX_SIDE then
		return nil, AdvMat.L( "import.error_dims", {
			size = AdvMat.Gen.DimText( info.w, info.h ), max = MAX_SIDE,
		} )
	end

	local path, why = Store( data, info )
	if not path then return nil, why end

	if not IMP.Material( path ) then
		pcall( file.Delete, DataPath( path ) )
		return nil, AdvMat.L( "import.error_decode" )
	end

	Remember( path, name )
	return path
end

--- The recipe size for an image of `nw` x `nh`.
---
--- Each side goes to the NEAREST size the generators offer, not to the
--- largest one below it the way a texture already in the game is read. An
--- imported picture is the finished image as its author wants it: snapping a
--- 1000 pixel sheet down to 512 throws three quarters of it away, where 1024
--- adds two percent. The pair is then shrunk together under this client's
--- ceiling, keeping its shape.
local function SizeFor( nw, nh )
	local GEN = AdvMat.Gen

	local function Nearest( n )
		local best, gap = GEN.SIZES[ 1 ], math.huge

		for _, size in ipairs( GEN.SIZES ) do
			local d = math.abs( math.log( size / n ) )
			if d < gap then best, gap = size, d end
		end

		return best
	end

	local w, h = GEN.FitWithin( Nearest( nw ), Nearest( nh ), GEN.MaxSize() )

	-- Only a sheet more than thirty times longer than it is wide halves its
	-- short side off the ladder. Its recipe stays valid at the smallest size.
	return math.max( w, GEN.SIZES[ 1 ] ), math.max( h, GEN.SIZES[ 1 ] )
end

---------------------------------------------------------------------------
-- Is importing possible here?
---------------------------------------------------------------------------

local function API()
	local hotloader = mmdhl
	local FA = istable( hotloader ) and hotloader.FileAccess or nil

	if istable( FA ) and isfunction( FA.Pick ) and isfunction( FA.Read )
		and isfunction( FA.IsAvailable ) then
		return FA
	end

	return nil
end

--- Single player, or the host of a listen server: the only places Model
--- Hotloader lets an addon read files, because everywhere else every client
--- script comes from somebody else's server.
local function LocalHost()
	if game and isfunction( game.SinglePlayer ) and game.SinglePlayer() then return true end

	local ply = LocalPlayer()
	return IsValid( ply ) and isfunction( ply.IsListenServerHost )
		and ply:IsListenServerHost() or false
end

--- ok, code, reason, asked of Model Hotloader now. See IMP.Status.
local function Query()
	local FA = API()

	-- On somebody else's server this player's Model Hotloader would refuse,
	-- if that server runs it at all - so installing it is not the fix there.
	if not FA then
		if not LocalHost() then return false, "unavailable_remote" end
		return false, istable( mmdhl ) and "update" or "missing"
	end

	local called, available, why, which = pcall( FA.IsAvailable )
	if not called then return false, "error", tostring( available ) end
	if available == true then return true, "ready" end

	local code   = isstring( which ) and which ~= "" and which or "unavailable"
	local reason = isstring( why ) and why ~= "" and why or nil

	-- A binary from before file access existed: the same fix as no binary.
	if code == "needs_update" then code = "update" end

	-- Model Hotloader says unavailable_remote on somebody else's server and in
	-- single player whose server half failed to load alike; only its sentence
	-- tells them apart. The second is an installation problem, not a reason to
	-- go and host a game.
	if code == "unavailable_remote" and LocalHost() then code = "no_server_realm" end

	return false, code, reason
end

local status, statusUntil, announced
local refreshQueued = false

local function Keep( ok, code, reason )
	status      = { ok = ok, code = code, reason = reason }
	statusUntil = RealTime() + STATUS_SECONDS
end

--- ok, code, reason - whether this client can import right now and, if not,
--- why: "missing" (no Model Hotloader at all), "update" (its Lua is there but
--- file access is not: the native module did not load, or it is older than
--- 2.3.0), "unavailable_remote" (somebody else's server), "no_server_realm"
--- (single player whose server half failed), or Model Hotloader's own code -
--- "disabled", "worker_missing" and so on - with its own sentence as `reason`.
---
--- `fresh` asks again now instead of reusing a recent answer.
function IMP.Status( fresh )
	if status and not fresh and RealTime() < statusUntil then
		return status.ok, status.code, status.reason
	end

	local ok, code, reason = Query()
	Keep( ok, code, reason )

	if announced == nil then
		announced = code
	elseif code ~= announced and not refreshQueued then
		-- A change no event announced, such as the switch flipped in a second copy
		-- of the game. The editors hear of it on the next frame, never from inside
		-- the list build that happened to ask.
		refreshQueued = true
		timer.Simple( 0, function()
			refreshQueued = false
			IMP.Refresh()
		end )
	end

	return ok, code, reason
end

--- Whether the texture rows should offer Import.
function IMP.Ready()
	return ( IMP.Status() ) == true
end

--- Ask again, and tell open editors when the answer changed so their rows
--- gain or lose Import.
function IMP.Refresh()
	local ok, code, reason = Query()
	Keep( ok, code, reason )
	if code == announced then return end

	announced = code
	hook.Run( "AdvMatImportChanged", code )
end

-- Model Hotloader announces everything that can change the answer: its file
-- access loading a frame after its Lua, the player's switch and folders, and
-- the verdict on the worker process that shows its windows. Answered on the
-- next frame: rebuilding editors inside its own dispatch would turn an error
-- in a list build into one in Model Hotloader's event, skipping its listeners.
for _, event in ipairs( {
	"MMDHL.FileAccessReady", "MMDHL.FileAccessChanged", "MMDHL.InstallationChanged",
} ) do
	hook.Add( event, "AdvMat.Import", function() timer.Simple( 0, IMP.Refresh ) end )
end

---------------------------------------------------------------------------
-- Importing
---------------------------------------------------------------------------

-- One import at a time. Model Hotloader shows one window at a time anyway,
-- and a second click while it is open (often behind the game) means the
-- player is looking for it. Holds the RealTime the request was made, so a
-- callback that never came cannot refuse every later import: Model Hotloader
-- promises exactly one, but a map change or a broken install is not worth a
-- dead button for the rest of the session.
local pending = false
local PENDING_SECONDS = 30 * 60

local function Notify( text, kind, seconds )
	AdvMat.NotifyLocal( text, kind or NOTIFY_GENERIC, seconds or 6 )
end

local function Failed( reason )
	Notify( AdvMat.L( "import.failed", { reason = tostring( reason or "?" ) } ),
		NOTIFY_ERROR, 8 )
end

local function TooLarge()
	return AdvMat.L( "import.error_large", { size = math.floor( MAX_BYTES / 1048576 ) } )
end

--- Model Hotloader's own sentence for a refusal code, when it has one.
local function Refusal( FA, code )
	if isfunction( FA.Message ) and isstring( code ) then
		local ok, text = pcall( FA.Message, code )
		if ok and isstring( text ) and text ~= "" then return text end
	end

	return AdvMat.L( "import.error_unreadable" )
end

--- Read a picked file whole, a chunk at a time.
local function ReadAll( item, done )
	local parts, total = {}, 0

	local function Next()
		-- Guarded: this runs inside Model Hotloader's callback, which would
		-- swallow an error and leave the import waiting for good.
		local called, err = pcall( item.Read, item,
			{ mode = "binary", offset = total, maxBytes = READ_CHUNK },
			function( ok, data, info )
				-- A failure's second value is Model Hotloader's own sentence.
				if not ok then done( nil, data ) return end
				if not isstring( data ) then done( nil, AdvMat.L( "import.error_unreadable" ) ) return end

				parts[ #parts + 1 ] = data
				total = total + #data
				if total > MAX_BYTES then done( nil, TooLarge() ) return end

				-- A short read is the end when the reply does not say. An empty
				-- one ends it regardless, rather than asking forever.
				local eof = istable( info ) and info.eof
				if eof == nil then eof = #data < READ_CHUNK end

				if eof or #data == 0 then
					done( table.concat( parts ) )
					return
				end

				Next()
			end )

		if not called then done( nil, tostring( err ) ) end
	end

	Next()
end

--- Turn the bytes of a picked file into a recipe and hand it over.
local function Finish( data, name, target, adopt )
	local info = Inspect( data )
	if not info then Failed( AdvMat.L( "import.error_format" ) ) return end

	if info.w > MAX_SIDE or info.h > MAX_SIDE then
		Failed( AdvMat.L( "import.error_dims", {
			size = AdvMat.Gen.DimText( info.w, info.h ), max = MAX_SIDE,
		} ) )
		return
	end

	local path, why = Store( data, info )
	if not path then Failed( why ) return end

	-- The engine is the decoder. What it cannot open - a CMYK JPEG, an unusual
	-- PNG - is turned away here, not discovered later as a missing texture.
	if not IMP.Material( path ) then
		pcall( file.Delete, DataPath( path ) )
		Failed( AdvMat.L( "import.error_decode" ) )
		return
	end

	Remember( path, name )

	local w, h = SizeFor( info.w, info.h )
	local recipe = { kind = "edit", src = path, size = w, ops = {}, sourcecopy = true }
	if h ~= w then recipe.height = h end

	-- The texture editor's own reading of a new source: the alpha channel is
	-- transparency only when the material says so ($translucent or $alphatest).
	-- Otherwise its bytes are kept as the shader data an opaque Source
	-- material uses it for, and the image is shown solid.
	local shows = istable( target ) and target.showsalpha == true
	if not ( shows and info.alpha ) then recipe.opaque = true end

	local clean = AdvMat.Gen.Sanitize( recipe )
	if not clean then Failed( AdvMat.L( "import.error_recipe" ) ) return end

	-- `transparent` says the image's alpha is meant as holes, which decides
	-- whether a $translucent the replaced recipe installed stays with it.
	if adopt( clean, { transparent = clean.opaque ~= true } ) == false then
		Failed( AdvMat.L( "import.error_closed" ) )
		return
	end

	-- Start the multiplayer upload now rather than at Save, as the texture
	-- editor does when it hands an edit back. One refusal is worth saying at
	-- once: a finished texture over the server's limit for shared images can
	-- never be saved, and every Save would rebuild it to find that out again.
	if AdvMat.Assets and isfunction( AdvMat.Assets.StageEdit ) then
		AdvMat.Assets.StageEdit( clean, function( staged )
			if staged then return end

			local limit = isfunction( AdvMat.Assets.MaxBytes ) and AdvMat.Assets.MaxBytes() or nil
			local bytes = tonumber( file.Size( AdvMat.Gen.FileName( clean ), "DATA" ) ) or -1
			if not limit or bytes <= limit then return end

			Notify( AdvMat.L( "import.too_large_to_save", {
				size = math.ceil( bytes / 1048576 ), limit = math.floor( limit / 1048576 ),
			} ), NOTIFY_ERROR, 10 )
		end )
	end

	local shown = IMP.Name( path ) or AdvMat.L( "import.image" )
	local size  = AdvMat.Gen.DimText( w, h )

	if w == info.w and h == info.h then
		Notify( AdvMat.L( "import.done", { name = shown, size = size } ) )
	else
		Notify( AdvMat.L( "import.done_resized", {
			name = shown, size = size, native = AdvMat.Gen.DimText( info.w, info.h ),
		} ) )
	end
end

--- Ask the player for an image and give `param` an edit recipe made from it.
---
---     target  the row's ctx.Target(): the slot the texture editor would be
---             told about, which decides how the image's alpha is read
---     adopt   function( recipe ), returning false when the editor that
---             asked has gone - which then gets nothing
---
--- Everything after the request arrives in callbacks a frame or more later;
--- nothing here waits.
function IMP.Pick( param, target, adopt )
	if pending and RealTime() - pending < PENDING_SECONDS then
		Notify( AdvMat.L( "import.busy" ), NOTIFY_HINT, 8 )
		return false
	end

	-- Asked fresh: a button built before file access was switched off must
	-- explain itself rather than open a request that can only fail.
	local FA = API()
	if not FA or not IMP.Status( true ) then
		IMP.OpenResolve( istable( target ) and target.host or nil )
		return false
	end

	pending = RealTime()

	local asked, err = pcall( FA.Pick, {
		addon   = ADDON,
		title   = AdvMat.L( "import.picker_title", { param = tostring( param or "" ) } ),
		purpose = AdvMat.L( "import.purpose" ),
		filters = { { AdvMat.L( "import.filter" ), "*.png;*.jpg;*.jpeg" } },
	}, function( picked, items, refused )
		if not picked then
			pending = false

			-- Closing the window is an answer, not a failure worth a message.
			-- Otherwise `items` is Model Hotloader's sentence and `refused` its code.
			if refused ~= "denied" then Failed( items ) end
			return
		end

		local item = istable( items ) and items[ 1 ] or nil

		if not item then
			pending = false
			local first = istable( refused ) and refused[ 1 ] or nil
			Failed( Refusal( FA, istable( first ) and first.code or nil ) )
			return
		end

		if ( tonumber( item.size ) or 0 ) > MAX_BYTES then
			item:Release()
			pending = false
			Failed( TooLarge() )
			return
		end

		ReadAll( item, function( data, reason )
			item:Release()
			pending = false

			if not data then Failed( reason ) return end
			Finish( data, item.name, target, adopt )
		end )
	end )

	if not asked then
		pending = false
		Failed( err )
		return false
	end

	return true
end

---------------------------------------------------------------------------
-- Saying why not
---------------------------------------------------------------------------

local NOTICE = {
	missing            = "import.notice_missing",
	update             = "import.notice_update",
	disabled           = "import.notice_disabled",
	unavailable_remote = "import.notice_remote",
}

local function NoticeText( code )
	return AdvMat.L( NOTICE[ code ] or "import.notice_other" )
end

--- A button as wide as its own label, so no translation is cut short.
local function FitWide( button, minimum )
	surface.SetFont( "AdvMatText" )
	button:SetWide( math.max( minimum or 0, surface.GetTextSize( button:GetText() ) + 24 ) )
end

--- One small line at the top of a parameter list when importing is not
--- possible here, with a Resolve button that explains the fix. When it is
--- possible there is nothing to say: every texture row offers Import itself.
function IMP.CreateNotice( parent, host )
	local ok, code = IMP.Status()
	if ok or not IsValid( parent ) then return nil end

	local text = NoticeText( code )

	local bar = parent:Add( "DPanel" )
	bar:Dock( TOP )
	bar:DockMargin( 0, 0, 6, 4 )
	bar:SetTall( AdvMat.RowHeight() )
	bar.Paint = function( _, w, h )
		surface.SetDrawColor( T.Row.r, T.Row.g, T.Row.b, 255 )
		surface.DrawRect( 0, 0, w, h )
		surface.SetDrawColor( T.Warn.r, T.Warn.g, T.Warn.b, 255 )
		surface.DrawRect( 0, 0, 3, h )
	end

	-- Created before the text: a FILL child claims everything that is left at
	-- the moment it is added.
	local resolve = vgui.Create( "DButton", bar )
	resolve:Dock( RIGHT )
	resolve:DockMargin( 4, 3, 4, 3 )
	resolve:SetText( AdvMat.L( "import.resolve" ) )
	resolve:SetTooltip( AdvMat.L( "import.resolve_tip" ) )
	AdvMat.StyleButton( resolve )
	FitWide( resolve, AdvMat.FontSize * 5 )
	resolve.DoClick = function() IMP.OpenResolve( host ) end

	local label = vgui.Create( "DLabel", bar )
	label:Dock( FILL )
	label:DockMargin( 10, 0, 4, 0 )
	label:SetText( text )
	label:SetWrap( true )
	label:SetTooltip( text )
	AdvMat.StyleLabel( label, "AdvMatSmall", T.Warn )

	-- A translated sentence can outgrow one line in the narrow inspector, so
	-- the strip measures its wrapped text and grows instead of cutting it off.
	-- The button stays one row high in the middle.
	bar.PerformLayout = function( self, w )
		local width = w - resolve:GetWide() - 22
		if width <= 40 then return end

		local rowH  = AdvMat.RowHeight()
		local lines = math.max( 1, #AdvMat.WrapText( label:GetText(), "AdvMatSmall", width ) )
		local tall  = math.max( rowH, lines * ( AdvMat.FontSize + 2 ) + 8 )
		if self:GetTall() == tall then return end

		self:SetTall( tall )

		local pad = math.max( 3, math.floor( ( tall - rowH ) * 0.5 ) + 3 )
		resolve:DockMargin( 4, pad, 4, pad )

		local holder = self:GetParent()
		if IsValid( holder ) then
			holder:InvalidateLayout()
			holder:InvalidateParent()
		end
	end

	return bar
end

---------------------------------------------------------------------------
-- The Resolve window
---------------------------------------------------------------------------
-- Kept as AdvMat.ImportHelp, beside the editors' other child windows, so the
-- editor that opened it closes it too.

local function Paragraph( parent, text, colour, font )
	local label = parent:Add( "DLabel" )
	label:Dock( TOP )
	label:DockMargin( 0, 0, 0, 8 )
	label:SetWrap( true )
	label:SetAutoStretchVertical( true )
	label:SetText( text )
	AdvMat.StyleLabel( label, font or "AdvMatText", colour or T.Text )
	return label
end

local function Action( parent, key, fn )
	local button = parent:Add( "DButton" )
	button:Dock( TOP )
	button:SetTall( AdvMat.RowHeight() )
	button:DockMargin( 0, 0, 0, 8 )
	button:SetText( AdvMat.L( key ) )
	AdvMat.StyleButton( button )
	button.DoClick = fn
	return button
end

--- A caption, the address itself - selectable, for when the Steam overlay is
--- off - and buttons to open or copy it.
local function LinkRow( parent, caption, url )
	Paragraph( parent, caption, T.Text, "AdvMatBold" ):DockMargin( 0, 4, 0, 2 )

	local row = parent:Add( "DPanel" )
	row:Dock( TOP )
	row:SetTall( AdvMat.RowHeight() )
	row:DockMargin( 0, 0, 0, 8 )
	row.Paint = AdvMat.NoPaint

	local open = vgui.Create( "DButton", row )
	open:Dock( RIGHT )
	open:DockMargin( 4, 0, 0, 0 )
	open:SetText( AdvMat.L( "import.open_link" ) )
	AdvMat.StyleButton( open )
	FitWide( open, AdvMat.FontSize * 6 )
	open.DoClick = function() gui.OpenURL( url ) end

	local copy = vgui.Create( "DButton", row )
	copy:Dock( RIGHT )
	copy:DockMargin( 4, 0, 0, 0 )
	copy:SetText( AdvMat.L( "import.copy_link" ) )
	AdvMat.StyleButton( copy )
	FitWide( copy, AdvMat.FontSize * 6 )
	copy.DoClick = function()
		SetClipboardText( url )
		Notify( AdvMat.L( "import.copied" ), NOTIFY_GENERIC, 3 )
	end

	local address = vgui.Create( "DTextEntry", row )
	address:Dock( FILL )
	address:SetValue( url )
	address:SetEditable( false )
	AdvMat.StyleEntry( address )

	return row
end

--- What hot material import needs, why it is not available here, and where
--- to get Model Hotloader.
function IMP.OpenResolve( host )
	if IsValid( AdvMat.ImportHelp ) then AdvMat.ImportHelp:Remove() end

	host = IsValid( host ) and host or ( IsValid( AdvMat.Editor ) and AdvMat.Editor or nil )

	local ok, code, reason = IMP.Status( true )
	local FA = API()
	local hotloader = mmdhl
	local fs, rowH = AdvMat.FontSize, AdvMat.RowHeight()

	local frame = vgui.Create( "DFrame" )
	AdvMat.ImportHelp = frame
	frame.AdvMatHost = host
	frame:SetMinWidth( math.min( fs * 30, math.max( 1, ScrW() - 24 ) ) )
	frame:SetMinHeight( math.min( fs * 20, math.max( 1, ScrH() - 24 ) ) )
	frame:SetSize( math.min( fs * 44, ScrW() - 80 ), math.min( fs * 36, ScrH() - 80 ) )
	frame:SetTitle( AdvMat.L( "import.resolve_title" ) )
	frame:SetSizable( true )
	frame:Center()
	frame:MakePopup()

	---------------------------------------------------------------- bottom
	-- Docked before the text, which fills what is left.
	local bottom = vgui.Create( "DPanel", frame )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH + 4 )
	bottom:DockMargin( 0, 6, 0, 0 )
	bottom.Paint = AdvMat.NoPaint

	local close = vgui.Create( "DButton", bottom )
	close:Dock( RIGHT )
	close:SetText( AdvMat.L( "common.close" ) )
	AdvMat.StyleButton( close )
	FitWide( close, fs * 6 )
	close.DoClick = function() frame:Close() end

	local again = vgui.Create( "DButton", bottom )
	again:Dock( RIGHT )
	again:DockMargin( 0, 0, 6, 0 )
	again:SetText( AdvMat.L( "import.check_again" ) )
	again:SetTooltip( AdvMat.L( "import.check_again_tip" ) )
	AdvMat.StyleButton( again )
	FitWide( again, fs * 8 )
	again.DoClick = function()
		IMP.Refresh()

		if IMP.Ready() then
			Notify( AdvMat.L( "import.now_ready" ), NOTIFY_GENERIC, 5 )
			frame:Close()
		else
			-- Rebuilt from scratch: the reason, and so the advice, may differ.
			IMP.OpenResolve( host )
		end
	end

	------------------------------------------------------------------ text
	local body = vgui.Create( "DScrollPanel", frame )
	body:Dock( FILL )

	if ok then
		Paragraph( body, AdvMat.L( "import.resolve_ready" ) )
	else
		Paragraph( body, NoticeText( code ), T.Warn, "AdvMatBold" )
		if reason then
			Paragraph( body, AdvMat.L( "import.resolve_reason", { reason = reason } ), T.TextDim )
		end
	end

	Paragraph( body, AdvMat.L( "import.resolve_about" ) )

	if not ok then
		local how = code == "disabled" and "import.resolve_disabled"
			or code == "unavailable_remote" and "import.resolve_remote"
			or ( code == "missing" or code == "update" ) and "import.resolve_install"
			or "import.resolve_other"
		Paragraph( body, AdvMat.L( how ) )

		-- Model Hotloader's own windows know more than this one: its installer
		-- names the exact file that is missing or was refused, and its file
		-- access manager holds the switch.
		if code == "disabled" and FA and isfunction( FA.OpenManager ) then
			Action( body, "import.open_file_access", function() FA.OpenManager() end )
		elseif code ~= "unavailable_remote" and istable( hotloader )
			and isfunction( hotloader.OpenInstallation ) then
			Action( body, "import.open_installation", function() hotloader.OpenInstallation() end )
		end
	end

	LinkRow( body, AdvMat.L( "import.link_workshop" ), WORKSHOP_URL )
	LinkRow( body, AdvMat.L( "import.link_github" ), GITHUB_URL )

	AdvMat.StyleFrame( frame )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.SetupFrame( frame, "import_help" )
		AdvMat.WindowUX.PlaceChild( frame, frame.AdvMatHost )
	end

	return frame
end
