--[[---------------------------------------------------------------------------
	Advanced Material Editor - RTX Remix client bridge

	This is the only addon file that talks to Remix globals.  The stock editor
	never calls it.  The bridge has three deliberately different capability
	classes:

	  * RemixMaterial tracking: discovers the 64-bit texture hash strings that
	    identify an already-rendered Source material.
	  * RemixMaterial CreateOpaqueMaterial: creates a new external material.  It
	    is reported for diagnostics but is NOT treated as a writer for a legacy
	    draw-call texture override; using it that way is API-version dependent
	    and can replace the wrong resource.
	  * AdvMatRTXBridge: an optional, version-pinned native writer which explicitly
	    promises legacy-material replacement semantics.

	Native writer contract (global `AdvMatRTXBridge`, API_VERSION exactly 1):

	  Capabilities() -> {
	    legacyMaterialOverrides = true,
	    livePreview = boolean, textureWriter = boolean
	  }

	  ApplyLegacyMaterial( request ) -> true [, result] | false, reason
	  ClearLegacyMaterial( request ) -> true [, result] | false, reason
	  ClearAllOwned( request )       -> true [, result] | false, reason
	  RestorePreview( request )      -> true [, result] | false, reason (optional)

	`request` contains protocol=1, operation, target, hashes (always strings),
	profile and compiled.  Calls use dot semantics and are protected with pcall.
	Clients without that contract remain useful: committed profiles are exported
	under data/advmat/rtx_exports for a native/runtime-side importer.
-----------------------------------------------------------------------------]]

AdvMat           = AdvMat or {}
AdvMat.RTX       = AdvMat.RTX or {}
AdvMat.RTX.Bridge = AdvMat.RTX.Bridge or {}

local Bridge = AdvMat.RTX.Bridge

Bridge.CONTRACT_VERSION = 1
Bridge.ExportFolder     = "advmat/rtx_exports"
Bridge.NativeContract   = {
	global = "AdvMatRTXBridge",
	apiVersion = 1,
	requiredCapabilities = { legacyMaterialOverrides = true, authoritativeReset = true },
	requiredFunctions = {
		"Capabilities", "ApplyLegacyMaterial", "ClearLegacyMaterial", "ClearAllOwned",
	},
}
Bridge.HashCache        = Bridge.HashCache or {}
Bridge.HashWait         = Bridge.HashWait or {}
Bridge.ApplyQueue       = Bridge.ApplyQueue or {}
Bridge.ApplyGeneration  = Bridge.ApplyGeneration or {}
Bridge.ApplySerial      = tonumber( Bridge.ApplySerial ) or 0
Bridge.LastExport       = Bridge.LastExport or {}
Bridge.GeneratedWait    = Bridge.GeneratedWait or {}
Bridge.StandaloneTried  = Bridge.StandaloneTried or false
-- A watched replacement mod outlives Lua and the server that authored it.
-- Forget any autorefresh-era readiness here: every fresh load must reconcile
-- the provider's owned disk state before it may publish another profile.
Bridge.NativeSessionProvider = nil
Bridge.NativeSessionReady    = false
Bridge.NativeSessionError    = nil
Bridge.ExportSessionReady    = false
Bridge.SessionGeneration     = tonumber( Bridge.SessionGeneration ) or 0

local HASH_RETRIES       = 20
local HASH_RETRY_INTERVAL = 0.25
local PREVIEW_DEBOUNCE   = 0.20
local COMMIT_DEBOUNCE    = 0.12
-- A remote edited map is deliberately paced through the reliable net channel
-- (~120 KiB/s) so it cannot overflow the engine's small send buffer. Several
-- maps or players may be ahead of this request; keep the RTX materializer alive
-- while that bounded transfer is making progress.
local GENERATION_TIMEOUT = 600

-- An RTXFixesBinary integration registers AdvMatRTXBridge itself.  Developers
-- may instead place the ABI-matched standalone module in lua/bin.  Load that
-- module only after a callable Remix runtime answers; stock Garry's Mod never
-- probes or loads the native compatibility path.
local function RemixRuntimeAnswers()
	local config = rawget( _G, "RemixConfig" )
	if istable( config ) and isfunction( config.GetUIState ) then
		local ok, state = pcall( config.GetUIState )
		if ok and isnumber( state ) and state == state then
			local states = istable( config.UIState ) and config.UIState or {}
			local basic = tonumber( states.Basic ) or 1
			local advanced = tonumber( states.Advanced ) or 2
			if state == basic or state == advanced then return true end
		end
	end
	local pipeline = rawget( _G, "MaterialPipeline" )
	local topbr = istable( pipeline ) and pipeline.ToPBR or nil
	if istable( topbr ) and isfunction( topbr.IsInitialized ) then
		local ok, ready = pcall( topbr.IsInitialized )
		if ok and ready == true then return true end
	end
	return false
end

function Bridge.TryLoadStandalone()
	if istable( rawget( _G, "AdvMatRTXBridge" ) ) then return true end
	if Bridge.StandaloneTried or not RemixRuntimeAnswers() then return false end
	Bridge.StandaloneTried = true
	local ok, reason = pcall( require, "advmat_rtx_bridge" )
	if not ok then
		AdvMat.Log( "Optional RTX native bridge was not loaded: %s", tostring( reason ) )
		return false
	end
	return istable( rawget( _G, "AdvMatRTXBridge" ) )
end

local function LoadAndResetNative( force )
	Bridge.TryLoadStandalone()
	if RemixRuntimeAnswers() and isfunction( Bridge.EnsureNativeSession ) then
		Bridge.EnsureNativeSession( force == true )
	end
end

local function ResetClientSessionState()
	-- Texture identities and pending writer work belong to one connected game
	-- session.  Keeping any of them across a server/map transition can cause a
	-- newly edited material to inherit the previous server's 64-bit hash and
	-- reactivate an override that the authoritative reset just disabled.
	for material in pairs( Bridge.HashWait or {} ) do
		timer.Remove( "AdvMat.RTX.Hash." .. util.CRC( material ) )
	end
	for material in pairs( Bridge.ApplyQueue or {} ) do
		timer.Remove( "AdvMat.RTX.Apply." .. util.CRC( material ) )
	end
	for target in pairs( Bridge.GeneratedWait or {} ) do
		timer.Remove( "AdvMat.RTX.Generate." .. util.CRC( target ) )
	end
	Bridge.HashCache = {}
	Bridge.HashWait = {}
	Bridge.ApplyQueue = {}
	-- Keep the serial monotonic across session resets.  An asynchronous texture
	-- bake from the previous server must never acquire the same token as a new
	-- apply after this table is cleared.
	Bridge.ApplySerial = ( tonumber( Bridge.ApplySerial ) or 0 ) + 1
	Bridge.ApplyGeneration = {}
	Bridge.GeneratedWait = {}
	Bridge.NativeSessionProvider = nil
	Bridge.NativeSessionReady = false
	Bridge.NativeSessionError = nil
	Bridge.ExportSessionReady = false
end

timer.Simple( 0, function() LoadAndResetNative( false ) end )
hook.Add( "AdvMatBackendCapabilitiesChanged", "AdvMat.RTX.TryNativeBridge", function()
	LoadAndResetNative( false )
end )
-- InitPostEntity runs for every joined server/map.  The provider's disk state
-- is global to this Garry's Mod install, while the authoritative RTX database
-- belongs to the current server, so a new session must always begin empty.
hook.Add( "InitPostEntity", "AdvMat.RTX.ResetOwnedSession", function()
	ResetClientSessionState()
	LoadAndResetNative( true )
end )

local function TargetMaterial( value )
	if istable( value ) then
		value = value.target and value.target.material or value.material
	end
	return AdvMat.NormalizeMaterial( value or "" )
end

local function Copy( value )
	return istable( value ) and table.Copy( value ) or value
end

local function RemoveDataFile( path )
	if not file.Exists( path, "DATA" ) then return true end
	if not isfunction( file.Delete ) then return false, "DATA delete API is unavailable" end
	local ok, reason = pcall( file.Delete, path )
	if not ok then return false, tostring( reason ) end
	if file.Exists( path, "DATA" ) then return false, "file remained after delete" end
	return true
end

local function Callback( fn, ... )
	if not isfunction( fn ) then return end
	local ok, err = pcall( fn, ... )
	if not ok then AdvMat.Log( "RTX bridge callback failed: %s", tostring( err ) ) end
end

local function NormalizeHash( raw )
	-- Never accept the numeric result of GetTextureHash: Lua numbers cannot
	-- exactly represent arbitrary 64-bit identifiers.  Remix's string return is
	-- the authoritative form all the way through JSON and the writer contract.
	if not isstring( raw ) then return nil end
	local text = string.upper( string.Trim( raw ) )
	local body = string.match( text, "^0X([0-9A-F]+)$" ) or string.match( text, "^([0-9A-F]+)$" )
	if not body or #body < 1 or #body > 16 then return nil end
	if not string.find( body, "[1-9A-F]" ) then return nil end
	body = string.rep( "0", 16 - #body ) .. body
	return "0x" .. body
end

local function NormalizeHashes( raw )
	local out, seen = {}, {}
	if not istable( raw ) then return out end

	for _, value in pairs( raw ) do
		local hash = NormalizeHash( value )
		if hash and not seen[ hash ] then
			seen[ hash ] = true
			out[ #out + 1 ] = hash
		end
	end

	table.sort( out )
	return out
end

local function RemixTable()
	local value = rawget( _G, "RemixMaterial" )
	return istable( value ) and value or nil
end

local function PipelineTable()
	local value = rawget( _G, "MaterialPipeline" )
	return istable( value ) and istable( value.ToPBR ) and value.ToPBR or nil
end

local function RawWriterProvider()
	local provider = rawget( _G, "AdvMatRTXBridge" )
	if not istable( provider ) or tonumber( provider.API_VERSION ) ~= Bridge.CONTRACT_VERSION then
		return nil, "no compatible AdvMatRTXBridge v1 provider"
	end
	if not isfunction( provider.Capabilities )
		or not isfunction( provider.ApplyLegacyMaterial )
		or not isfunction( provider.ClearLegacyMaterial )
		or not isfunction( provider.ClearAllOwned ) then
		return nil, "AdvMatRTXBridge v1 is missing required functions"
	end

	local ok, caps = pcall( provider.Capabilities )
	if not ok or not istable( caps ) then
		return nil, "AdvMatRTXBridge.Capabilities failed"
	end
	if caps.legacyMaterialOverrides ~= true then
		return nil, "native provider does not promise legacy material overrides"
	end
	if caps.authoritativeReset ~= true then
		return nil, "native provider cannot reset cross-server owned state"
	end

	return provider, caps
end

--- Reconcile persistent native state at the start of a client/server session.
--- The bridge's watched mod is process- and server-global; without this reset,
--- a hash saved on server A would remain active on server B, which has no way
--- to send A's tombstone.  Only the native provider may enumerate its fixed
--- owned directory, so Lua supplies no paths or hashes here.
function Bridge.EnsureNativeSession( force )
	if not RemixRuntimeAnswers() then
		Bridge.NativeSessionProvider = nil
		Bridge.NativeSessionReady = false
		Bridge.NativeSessionError = "RTX Remix runtime is not ready"
		return nil, Bridge.NativeSessionError
	end
	local provider, capsOrError = RawWriterProvider()
	if not provider then
		Bridge.NativeSessionProvider = nil
		Bridge.NativeSessionReady = false
		Bridge.NativeSessionError = capsOrError
		return nil, capsOrError
	end

	if not force and Bridge.NativeSessionProvider == provider then
		if Bridge.NativeSessionReady then return provider, capsOrError end
		return nil, Bridge.NativeSessionError or "native owned-state reset failed"
	end

	Bridge.NativeSessionProvider = provider
	Bridge.NativeSessionReady = false
	Bridge.NativeSessionError = nil
	local request = {
		protocol = Bridge.CONTRACT_VERSION,
		operation = "session-reset",
	}
	local ok, accepted, detail = pcall( provider.ClearAllOwned, request )
	if not ok or accepted ~= true then
		local reason = tostring( ok and detail or accepted )
		Bridge.NativeSessionError = reason
		AdvMat.Log( "RTX native owned-state reset failed: %s", reason )
		return nil, reason
	end

	Bridge.NativeSessionReady = true
	Bridge.SessionGeneration = Bridge.SessionGeneration + 1
	Bridge.NativeSessionError = nil
	return provider, capsOrError
end

local function PrepareExportSession()
	if Bridge.ExportSessionReady then return true end
	if not file or not isfunction( file.Find ) or not isfunction( file.Delete )
		or not isfunction( file.Exists ) then
		return false, "DATA export cleanup API is unavailable"
	end

	local ok, names = pcall( file.Find, Bridge.ExportFolder .. "/*", "DATA" )
	if not ok or not istable( names ) then return false, "could not enumerate prior RTX exports" end
	for _, name in ipairs( names ) do
		-- file.Find returns basenames.  Keep deletion confined to files emitted by
		-- ExportFileName; never accept separators or caller-supplied paths here.
		if isstring( name ) and ( string.match( name, "^[%w_%-]+%.json$" )
			or string.match( name, "^[%w_%-]+%.json%.pending%.json$" )
			or string.match( name, "^[%w_%-]+%.json%.backup%.json$" )
			-- Old development builds used disallowed final extensions.  A custom
			-- file layer may nevertheless have created them, so keep cleanup-only
			-- compatibility without ever writing those names again.
			or string.match( name, "^[%w_%-]+%.json%.tmp$" )
			or string.match( name, "^[%w_%-]+%.json%.bak$" ) ) then
			local path = Bridge.ExportFolder .. "/" .. name
			local removed = RemoveDataFile( path )
			if not removed then return false, "could not remove prior RTX export " .. name end
		end
	end
	Bridge.LastExport = {}
	Bridge.ExportSessionReady = true
	Bridge.SessionGeneration = Bridge.SessionGeneration + 1
	return true
end

--- Prepare the persistent writer before asking the server for its authoritative
--- profile snapshot.  A missing provider is safe export-only mode.  A provider
--- which is present but incompatible, or whose owned-state reset failed, is not:
--- acknowledging the snapshot in that state would let the server retire cleanup
--- history while stale global USD layers were still active on this client.
function Bridge.PrepareAuthoritativeSync()
	Bridge.TryLoadStandalone()
	-- Export bundles are also server-scoped instructions.  Clear the fixed owned
	-- export directory once per connection so a hashless draft from server A
	-- cannot be consumed after joining server B, where no tombstone can name it.
	local exportsReady, exportError = PrepareExportSession()
	if not exportsReady then return false, exportError end
	local installed = rawget( _G, "AdvMatRTXBridge" )
	if installed == nil then return true, { status = "export-only" } end
	if not istable( installed ) then
		return false, "AdvMatRTXBridge exists but is not a compatible provider table"
	end

	-- A failed reset never announced protocol 3, so retrying the same provider is
	-- safe. Do not cache a transient file lock for the rest of the map session.
	local retryFailedReset = Bridge.NativeSessionProvider == installed
		and Bridge.NativeSessionReady ~= true
	local provider, reason = Bridge.EnsureNativeSession( retryFailedReset )
	if provider then return true, { status = "native-reset" } end
	return false, tostring( reason or "native owned-state reset failed" )
end

local function WriterProvider()
	return Bridge.EnsureNativeSession( false )
end

--- A complete capability report for the RTX editor and its diagnostics view.
function Bridge.Capabilities()
	local remix = RemixTable()
	local pipe  = PipelineTable()
	local provider, native = WriterProvider()
	local providerPresent = rawget( _G, "AdvMatRTXBridge" ) ~= nil

	local tracking = remix and isfunction( remix.TrackMaterial )
		and ( isfunction( remix.GetAllTextureHashes ) or isfunction( remix.GetTextureHash ) ) or false
	local external = remix and isfunction( remix.CreateOpaqueMaterial ) or false

	return {
		contractVersion = Bridge.CONTRACT_VERSION,
		tracking        = tracking,
		inspection      = pipe and isfunction( pipe.InspectMaterial ) or false,
		pipeline        = istable( rawget( _G, "RTXMaterialPipeline" ) )
			and isfunction( rawget( _G, "RTXMaterialPipeline" ).ProcessMaterial ) or false,
		nativeWriter    = provider ~= nil,
		nativeProviderPresent = providerPresent,
		nativeBlocked   = providerPresent and provider == nil,
		nativeError     = provider == nil and tostring( native or "native writer unavailable" ) or nil,
		livePreview     = provider ~= nil and native.livePreview == true
			and native.reversiblePreview == true and isfunction( provider.RestorePreview ),
		textureWriter   = provider ~= nil and native.textureWriter == true,
		exportOnly      = not providerPresent,
		externalMaterialAPI = external,
		-- This distinction is important.  The public API creates a standalone
		-- Remix material, but this editor needs replacement semantics for hashes
		-- captured from an existing Source draw call.
		externalAPIReplacesLegacy = false,
	}
end

function Bridge.HasNativeWriter()
	return WriterProvider() ~= nil
end

--- What the installed native writer accepts as one texture. The bridge that
--- ships with this client reports 2048 px and 32 MiB; an older one says
--- nothing, and those were its limits too. A later build copies a DDS up to
--- maxTexture* and reports the smaller limits it decodes a picture to as
--- maxDecodedTexture*; for one without them the two are the same.
function Bridge.NativeLimits()
	local provider, caps = WriterProvider()
	caps = provider and istable( caps ) and caps or {}
	local dimension = tonumber( caps.maxTextureDimension ) or 2048
	local bytes = tonumber( caps.maxTextureBytes ) or 32 * 1024 * 1024
	return {
		maxTextureDimension = dimension,
		maxTextureBytes     = bytes,
		maxDecodedTextureDimension = tonumber( caps.maxDecodedTextureDimension ) or dimension,
		maxDecodedTextureBytes     = tonumber( caps.maxDecodedTextureBytes ) or bytes,
	}
end

--- The size a recipe's picture reaches the native writer at: its own, or
--- halved until it fits the writer's decode limits - 4 bytes a pixel plus a
--- third for the mips, as cl_28_rtx_enhance.lua counts - but never below the
--- generator's smallest size. Returns width, height and whether that is
--- smaller than the recipe; without the generator, nothing is known.
function Bridge.WriterSize( recipe )
	local generator = AdvMat.Gen
	if not generator or not isfunction( generator.Dims ) then return nil, nil, false end
	local w, h = generator.Dims( recipe )
	if not Bridge.HasNativeWriter() then return w, h, false end

	local limits = Bridge.NativeLimits()
	local side, bytes = limits.maxDecodedTextureDimension, limits.maxDecodedTextureBytes
	local smallest = generator.SIZES and generator.SIZES[ 1 ] or 1
	local fw, fh = w, h
	while ( fw > side or fh > side or fw * fh * 16 / 3 > bytes ) and ( fw > smallest or fh > smallest ) do
		fw = math.max( smallest, math.floor( fw / 2 ) )
		fh = math.max( smallest, math.floor( fh / 2 ) )
	end
	return fw, fh, fw ~= w or fh ~= h
end

local function ReadHashesNow( material )
	local remix = RemixTable()
	if not remix then return {} end

	if isfunction( remix.TrackMaterial ) then pcall( remix.TrackMaterial, material ) end

	if isfunction( remix.GetAllTextureHashes ) then
		local ok, hashes = pcall( remix.GetAllTextureHashes, material )
		if ok then
			hashes = NormalizeHashes( hashes )
			if #hashes > 0 then return hashes end
		end
	end

	-- Older pinned clients expose only GetTextureHash.  Its first return is a
	-- lossy Lua number; deliberately consume only the second, hexadecimal one.
	if isfunction( remix.GetTextureHash ) then
		local ok, _, hashString = pcall( remix.GetTextureHash, material )
		local hash = ok and NormalizeHash( hashString ) or nil
		if hash then return { hash } end
	end

	return {}
end

local function FinishHashWait( material, hashes, reason )
	local wait = Bridge.HashWait[ material ]
	if not wait then return end
	Bridge.HashWait[ material ] = nil
	timer.Remove( "AdvMat.RTX.Hash." .. util.CRC( material ) )

	for _, fn in ipairs( wait.callbacks ) do
		Callback( fn, Copy( hashes ), reason )
	end
end

--- Resolve captured texture identities for a Source material.  Returns the
--- current result synchronously.  With a callback, a material which has not
--- rendered yet is tracked and retried for five seconds.
function Bridge.ResolveHashes( material, callback )
	material = TargetMaterial( material )
	if material == "" then
		Callback( callback, {}, "empty material")
		return {}
	end

	local hashes = ReadHashesNow( material )
	if #hashes > 0 then
		Bridge.HashCache[ material ] = Copy( hashes )
		Callback( callback, Copy( hashes ) )
		return hashes
	end

	if not isfunction( callback ) then
		return Copy( Bridge.HashCache[ material ] or {} )
	end

	local remix = RemixTable()
	if not remix or not isfunction( remix.TrackMaterial )
		or ( not isfunction( remix.GetAllTextureHashes ) and not isfunction( remix.GetTextureHash ) ) then
		Callback( callback, {}, "Remix material tracking is unavailable" )
		return {}
	end

	local wait = Bridge.HashWait[ material ]
	if wait then
		wait.callbacks[ #wait.callbacks + 1 ] = callback
		return Copy( Bridge.HashCache[ material ] or {} )
	end

	wait = { attempts = 0, callbacks = { callback } }
	Bridge.HashWait[ material ] = wait

	local timerName = "AdvMat.RTX.Hash." .. util.CRC( material )
	timer.Create( timerName, HASH_RETRY_INTERVAL, HASH_RETRIES, function()
		if Bridge.HashWait[ material ] ~= wait then return end
		wait.attempts = wait.attempts + 1

		local found = ReadHashesNow( material )
		if #found > 0 then
			Bridge.HashCache[ material ] = Copy( found )
			FinishHashWait( material, found )
		elseif wait.attempts >= HASH_RETRIES then
			FinishHashWait( material, {}, "material has not produced a captured texture hash")
		end
	end )

	return Copy( Bridge.HashCache[ material ] or {} )
end

local function Compile( profile )
	local schema = AdvMat.RTXSchema
	if istable( schema ) and isfunction( schema.Compile ) then
		local ok, compiled, err = pcall( schema.Compile, profile )
		if ok and istable( compiled ) then return compiled end
		local reason = ok and err or compiled
		return nil, istable( reason ) and table.concat( reason, "; " ) or reason
	end

	-- Kept only for forward-compatible native providers during Lua autorefresh;
	-- normal installs always load the shared schema before this client file.
	if istable( profile ) and istable( profile.compiled ) then
		return Copy( profile.compiled )
	end
	return nil, "RTX schema compiler is unavailable"
end

local function FinishGenerated( target, ok, reason )
	local waiting = Bridge.GeneratedWait[ target ]
	if not waiting then return end
	Bridge.GeneratedWait[ target ] = nil
	timer.Remove( "AdvMat.RTX.Generate." .. util.CRC( target ) )
	for _, done in ipairs( waiting ) do Callback( done, ok, target, reason ) end
end

local function WaitForGenerated( recipe, done )
	local generator = AdvMat.Gen
	if not istable( generator ) or not isfunction( generator.Sanitize )
		or not isfunction( generator.FileName ) or not isfunction( generator.Request ) then
		Callback( done, false, nil, "generated-texture builder is unavailable" )
		return false
	end

	local ok, clean = pcall( generator.Sanitize, recipe )
	if not ok or not istable( clean ) then
		Callback( done, false, nil, "generated-texture recipe is invalid" )
		return false
	end

	local target = generator.FileName( clean )
	if not isstring( target ) or target == "" or string.find( target, "%.%." )
		or string.sub( target, 1, 1 ) == "/" or string.find( target, ":", 1, true ) then
		Callback( done, false, nil, "generated-texture path is unsafe" )
		return false
	end
	local assets = AdvMat.Assets
	local remotePending = assets and assets.Remote and assets.Remote[ target ] ~= nil
	if file.Exists( target, "DATA" ) and not remotePending then
		Callback( done, true, target )
		return true
	end

	local waiting = Bridge.GeneratedWait[ target ]
	if waiting then
		waiting[ #waiting + 1 ] = done
		return nil
	end
	Bridge.GeneratedWait[ target ] = { done }

	-- The asset transport owns inactivity/progress deadlines for remote edits.
	-- Its server queue may be making steady round-robin progress for longer than
	-- this local builder watchdog, so an absolute RTX timeout would falsely fail
	-- a healthy multiplayer download and strand the native apply.
	if not remotePending then
		local timerName = "AdvMat.RTX.Generate." .. util.CRC( target )
		timer.Create( timerName, GENERATION_TIMEOUT, 1, function()
			FinishGenerated( target, false, "generated texture timed out" )
		end )
	end
	generator.Request( clean )
	return nil
end

-- A recipe's picture larger than the writer decodes - Edit on a 4096 px
-- enhancement map makes one - goes over as a copy of the finished PNG halved
-- until it fits (N.Fit, cl_29_rtx_normals.lua). Not a smaller recipe: an
-- import's own file is only on the computer it was imported on, while every
-- client has the finished PNG; and other recipes keep reading the full-size
-- one. The normal map is left to its conversion, which halves it by averaging
-- directions. The profile keeps its own recipe.
local function FitForWriter( name, recipe, target, done )
	local normals = AdvMat.RTX.Normals
	local ok, clean = pcall( AdvMat.Gen.Sanitize, recipe )
	if not ok or not istable( clean ) or name == "normal"
		or not normals or not isfunction( normals.Fit ) then
		done( target )
		return
	end
	local _, _, smaller = Bridge.WriterSize( clean )
	if not smaller then done( target ) return end
	normals.Fit( target, Bridge.NativeLimits(), done )
end

-- A map taken from an RTX Remix enhancement names that mod's own DDS file.
-- The writer copies such a file as it is - unless it is bigger than the
-- writer takes, lies in a mod folder linked in from outside the game, or has
-- bake operations, which only work on an image. Those get a decoded stand-in
-- (cl_28_rtx_enhance.lua) as generatedFile, exactly as a recipe's PNG does;
-- the profile itself keeps naming the enhancement's file.
local function CarryEnhancementMaps( ready, done )
	local enhance = AdvMat.RTX.Enhance
	if not enhance or not Bridge.HasNativeWriter() then return true end

	local limits = Bridge.NativeLimits()
	local maps = ready.pbr and ready.pbr.maps or {}
	local carries = {}
	for mapName, descriptor in pairs( maps ) do
		local source = isstring( descriptor ) and descriptor
			or ( istable( descriptor ) and not istable( descriptor.recipe ) and descriptor.source ) or nil
		local ops = istable( descriptor ) and descriptor.ops or nil
		if source and enhance.NeedsCarry( source, ops, limits ) then
			carries[ #carries + 1 ] = { name = mapName, source = source, ops = ops }
		end
	end
	if #carries == 0 then return true end

	local left, failed, synchronous = #carries, false, true
	local finished = false
	for _, carry in ipairs( carries ) do
		enhance.RequestImage( carry.source, "carry", carry.name, limits, function( path, reason )
			if failed or finished then return end
			if not path then
				failed = true
				Callback( done, false, "could not prepare " .. tostring( carry.source ) .. ": " .. tostring( reason ) )
				return
			end
			maps[ carry.name ] = {
				source = carry.source, generated = true, generatedFile = path,
				ops = Copy( carry.ops or {} ),
			}
			left = left - 1
			if left == 0 then
				finished = true
				if not synchronous then Callback( done, true ) end
			end
		end )
	end
	synchronous = false
	if failed then return false end
	if finished then return true end
	return nil
end

-- Remix reads every replacement normal map as unsigned octahedral and never
-- reads inputs:encoding, so the picture the profile names is converted on its
-- way to the writer (cl_29_rtx_normals.lua) - last, because it may be one of
-- the recipes just built. Only this request changes: it names the octahedral
-- copy and says so, while the profile keeps its own picture and encoding.
local function ConvertNormalMap( ready, done )
	local normals = AdvMat.RTX.Normals
	local pbr = ready.pbr
	local map = pbr and pbr.maps and pbr.maps.normal
	if not normals or map == nil or not Bridge.HasNativeWriter() then return true end

	pbr.options = pbr.options or {}
	local plan, refusal = normals.Plan( map, pbr.options.normal_encoding )
	if not plan then
		if not refusal then return true end
		Callback( done, false, "normal map " .. tostring( isstring( map ) and map or map.source )
			.. ": " .. refusal )
		return false
	end

	local finished, failed, synchronous = false, false, true
	normals.Request( plan, Bridge.NativeLimits(), function( path, reason )
		if finished then return end
		finished = true
		if not path then
			failed = true
			Callback( done, false, "could not convert the normal map " .. tostring( plan.file )
				.. " for RTX Remix: " .. tostring( reason ) )
			return
		end
		pbr.maps.normal = {
			source = isstring( map ) and map or map.source, generated = true,
			generatedFile = path, ops = {},
			recipe = istable( map ) and Copy( map.recipe ) or nil,
		}
		pbr.options.normal_encoding = "octahedral"
		if not synchronous then Callback( done, true ) end
	end )
	synchronous = false
	if failed then return false end
	if finished then return true end
	return nil
end

-- Add an ephemeral DATA-relative path for every recipe-backed map.  The
-- persisted profile remains unchanged and keeps the recipe, allowing each
-- client to rebuild locally.  A native writer may convert generatedFile to a
-- runtime-readable DDS; the addon never claims the PNG itself is a Remix map.
local MaterializeRecipes

-- Enhancement stand-ins, then recipes, then the normal map. Each stage
-- finishes now or later; the result is true when everything finished before
-- returning, false once something failed, nil while work is still queued.
local function MaterializeCompiled( compiled, done )
	local ready = Copy( compiled )
	local state = nil
	local function Settle( ok, reason )
		if state ~= nil then return end
		state = ok
		if ok then Callback( done, true, ready ) else Callback( done, false, nil, reason ) end
	end
	local function Normals()
		local converted = ConvertNormalMap( ready, Settle )
		if converted == true then Settle( true ) end
	end
	local function Recipes()
		MaterializeRecipes( ready, function( ok, _, reason )
			if not ok then Settle( false, reason ) return end
			Normals()
		end )
	end

	local carried = CarryEnhancementMaps( ready, function( ok, reason )
		if not ok then Settle( false, reason ) return end
		Recipes()
	end )
	if carried == true then Recipes() end
	if state == true then return true, ready end
	if state == false then return false end
	return nil
end

MaterializeRecipes = function( ready, done )
	local maps = ready.pbr and ready.pbr.maps or {}
	local generator = AdvMat.Gen
	local jobs, byOutput = {}, {}
	for mapName, descriptor in pairs( maps ) do
		if istable( descriptor ) and istable( descriptor.recipe ) then
			jobs[ #jobs + 1 ] = {
				name = tostring( mapName ), descriptor = descriptor,
				recipe = descriptor.recipe,
			}
		end
	end
	if #jobs == 0 then
		Callback( done, true, ready )
		return true, ready
	end

	-- A generator recipe can read another generated map through its stable
	-- data/<filename> material path (for example, a normal made from an edited
	-- albedo).  Establish those dependencies before requesting any work; pairs()
	-- order is not a persistence contract and could otherwise build the consumer
	-- first on a fresh client.
	if istable( generator ) and isfunction( generator.Sanitize )
		and isfunction( generator.FileName ) then
		for _, job in ipairs( jobs ) do
			local ok, clean = pcall( generator.Sanitize, job.recipe )
			local pathOK, target = false, nil
			if ok and clean then pathOK, target = pcall( generator.FileName, clean ) end
			if pathOK and isstring( target ) and target ~= "" then
				job.source = AdvMat.NormalizeMaterial( clean.src or "" )
				job.output = AdvMat.NormalizeMaterial( "data/" .. target )
				byOutput[ job.output ] = job
			end
		end
		for _, job in ipairs( jobs ) do
			local dependency = byOutput[ job.source ]
			if dependency ~= job then job.dependency = dependency end
		end
	end

	table.sort( jobs, function( left, right ) return left.name < right.name end )
	local ordered, visiting, visited, cycle = {}, {}, {}, false
	local function Visit( job )
		if visited[ job ] then return end
		if visiting[ job ] then cycle = true return end
		visiting[ job ] = true
		if job.dependency then Visit( job.dependency ) end
		visiting[ job ] = nil
		visited[ job ] = true
		ordered[ #ordered + 1 ] = job
	end
	for _, job in ipairs( jobs ) do Visit( job ) end
	if cycle then
		Callback( done, false, nil, "generated-texture recipes contain a dependency cycle" )
		return false
	end

	local cursor, failed, completed = 1, false, false
	local function GenerateNext()
		local job = ordered[ cursor ]
		if not job then
			completed = true
			Callback( done, true, ready )
			return
		end
		WaitForGenerated( job.recipe, function( ok, target, reason )
			if failed then return end
			if not ok then
				failed = true
				Callback( done, false, nil, reason )
				return
			end
			FitForWriter( job.name, job.recipe, target, function( fitted, why )
				if failed then return end
				if not fitted then
					failed = true
					Callback( done, false, nil, why )
					return
				end
				job.descriptor.generatedFile = fitted
				cursor = cursor + 1
				GenerateNext()
			end )
		end )
	end
	GenerateNext()
	if failed then return false end
	if completed then return true, ready end
	return nil
end

hook.Add( "AdvMatGenerated", "AdvMat.RTX.GeneratedMaps", function( recipe, produced )
	local target = isstring( produced ) and produced or nil
	if not target and AdvMat.Gen and AdvMat.Gen.FileName then
		local ok, result = pcall( AdvMat.Gen.FileName, recipe )
		if ok then target = result end
	end
	if target and Bridge.GeneratedWait[ target ] then FinishGenerated( target, true ) end
end )

hook.Add( "AdvMatGenerationFailed", "AdvMat.RTX.GeneratedMaps", function( recipe, produced, reason )
	local target = isstring( produced ) and produced or nil
	if not target and AdvMat.Gen and AdvMat.Gen.FileName then
		local ok, result = pcall( AdvMat.Gen.FileName, recipe )
		if ok then target = result end
	end
	if target and Bridge.GeneratedWait[ target ] then
		FinishGenerated( target, false, reason or "generated texture build failed" )
	end
end )

local function ExportFileName( material )
	local safe = string.gsub( material, "[^%w_%-]+", "_" )
	safe = string.sub( safe, 1, 80 )
	return safe .. "_" .. util.CRC( material ) .. ".json"
end

local function WriteExportVerified( path, contents )
	if not isfunction( file.Write ) or not isfunction( file.Read )
		or not isfunction( file.Rename ) then
		return false, "verified atomic DATA write API is unavailable"
	end

	-- Stock Garry's Mod only permits DATA writes/renames whose final extension
	-- is on its allow-list.  `.json.tmp` and `.json.bak` are therefore invalid;
	-- preserve the transactional suffix while keeping `.json` last.
	local temporary, backup = path .. ".pending.json", path .. ".backup.json"
	local removed, removeError = RemoveDataFile( temporary )
	if not removed then return false, "could not clear export staging file: " .. tostring( removeError ) end
	local writeOK, writeResult = pcall( file.Write, temporary, contents )
	if not writeOK or writeResult == false then
		RemoveDataFile( temporary )
		return false, "RTX export staging write failed"
	end
	if file.Read( temporary, "DATA" ) ~= contents then
		RemoveDataFile( temporary )
		return false, "RTX export staging write could not be verified"
	end

	local hadPrevious = file.Exists( path, "DATA" )
	local previous = hadPrevious and file.Read( path, "DATA" ) or nil
	if hadPrevious and not isstring( previous ) then
		RemoveDataFile( temporary )
		return false, "existing RTX export could not be read before replacement"
	end

	if hadPrevious then
		removed, removeError = RemoveDataFile( backup )
		if not removed then
			RemoveDataFile( temporary )
			return false, "could not clear RTX export backup: " .. tostring( removeError )
		end
		local ok = pcall( file.Rename, path, backup )
		if not ok or file.Exists( path, "DATA" ) or file.Read( backup, "DATA" ) ~= previous then
			RemoveDataFile( temporary )
			return false, "could not stage the previous RTX export"
		end
	end

	local renamed = pcall( file.Rename, temporary, path )
	if not renamed or file.Read( path, "DATA" ) ~= contents then
		RemoveDataFile( path )
		if hadPrevious then pcall( file.Rename, backup, path ) end
		local recovered = not hadPrevious or file.Read( path, "DATA" ) == previous
		RemoveDataFile( temporary )
		return false, recovered and "RTX export replacement failed"
			or "RTX export replacement failed and its previous file could not be restored"
	end

	if hadPrevious then RemoveDataFile( backup ) end
	-- Best-effort retirement of transaction debris emitted by an older custom
	-- file provider.  These files never take part in rollback for this write.
	RemoveDataFile( path .. ".tmp" )
	RemoveDataFile( path .. ".bak" )
	return true
end

local function ExportCommitted( profile, compiled, hashes )
	local material = TargetMaterial( profile )
	if material == "" then return false, "empty material" end

	if not file.IsDir( AdvMat.DataFolder, "DATA" ) then file.CreateDir( AdvMat.DataFolder ) end
	if not file.IsDir( Bridge.ExportFolder, "DATA" ) then file.CreateDir( Bridge.ExportFolder ) end

	local payload = {
		format      = "advmat-rtx-material",
		version     = 1,
		contract    = Bridge.CONTRACT_VERSION,
		exported    = os.time(),
		target      = Copy( profile.target or { material = material } ),
		hashes      = Copy( hashes ),
		profile     = Copy( profile ),
		compiled    = Copy( compiled ),
		application = "export-only; requires an AdvMatRTXBridge v1 legacy-material writer",
	}

	local json = util.TableToJSON( payload, true )
	if not isstring( json ) or json == "" then return false, "could not encode RTX export" end

	local relative = Bridge.ExportFolder .. "/" .. ExportFileName( material )
	local signature = util.CRC( json )
	if Bridge.LastExport[ material ] ~= signature
		or not isfunction( file.Read ) or file.Read( relative, "DATA" ) ~= json then
		local written, writeError = WriteExportVerified( relative, json )
		if not written then return false, writeError end
		Bridge.LastExport[ material ] = signature
	end

	return true, relative
end

local function NativeCall( operation, profile, compiled, hashes, callback )
	local provider, capsOrError = WriterProvider()
	if not provider then
		if rawget( _G, "AdvMatRTXBridge" ) ~= nil then
			local result = {
				status = "native-blocked", live = false, exportOnly = false,
				error = tostring( capsOrError or "native writer failed its authoritative reset" ),
			}
			Callback( callback, false, result )
			return false, result
		end
		if operation == "commit" then
			local ok, pathOrError = ExportCommitted( profile, compiled, hashes )
			local result = {
				status = ok and "exported" or "failed",
				live = false,
				exportOnly = true,
				path = ok and pathOrError or nil,
				error = not ok and pathOrError or nil,
			}
			Callback( callback, ok, result )
			return ok, result
		end

		local result = {
			status = "unsupported",
			live = false,
			exportOnly = true,
			error = capsOrError,
		}
		Callback( callback, false, result )
		return false, result
	end

	if #hashes == 0 then
		local result = { status = "waiting-for-hash", live = false,
			error = "material has not produced a captured texture hash" }
		Callback( callback, false, result )
		return false, result
	end

	local request = {
		protocol  = Bridge.CONTRACT_VERSION,
		operation = operation,
		target    = Copy( profile.target or { material = TargetMaterial( profile ) } ),
		hashes    = Copy( hashes ),
		profile   = Copy( profile ),
		compiled  = Copy( compiled ),
	}

	local ok, accepted, detail = pcall( provider.ApplyLegacyMaterial, request )
	if not ok or accepted ~= true then
		local result = { status = "failed", live = false, error = tostring( ok and detail or accepted ) }
		Callback( callback, false, result )
		return false, result
	end

	local result = istable( detail ) and detail or {}
	result.status = result.status or "applied"
	result.live   = true
	result.writer = "AdvMatRTXBridge-v1"
	result.capabilities = Copy( capsOrError )
	Callback( callback, true, result )
	return true, result
end

local function ApplyIsCurrent( material, generation )
	return generation == nil or Bridge.ApplyGeneration[ material ] == generation
end

local function ApplyKey( operation, material )
	-- Cancelling an editor preview must never cancel a Save that is waiting for
	-- texture generation. Commits and previews have independent generations.
	return operation == "preview" and ( material .. "::preview" ) or material
end

local function Superseded( callback )
	Callback( callback, false, { status = "superseded", live = false } )
end

local function ApplyCompiled( operation, profile, compiled, callback, generation )
	local material = TargetMaterial( profile )
	if not ApplyIsCurrent( ApplyKey( operation, material ), generation ) then
		Superseded( callback )
		return false, { status = "superseded", live = false }
	end
	-- A locally submitted or server-confirmed profile records an exact hash set.
	-- Never widen it with whatever this particular client happens to render:
	-- the extra layer would have no matching ownership record or cleanup
	-- tombstone and could survive a later Clear. Hashless drafts may still be
	-- exported; reversible previews alone may resolve a client-local identity.
	local recorded = profile.target and ( profile.target.hashes
		or ( profile.target.hash and { profile.target.hash } ) ) or {}
	local immediate = NormalizeHashes( recorded )
	if #immediate > 0 or not Bridge.HasNativeWriter() then
		return NativeCall( operation, profile, compiled, immediate, callback )
	end
	if operation ~= "preview" then
		local result = {
			status = "waiting-for-hash", live = false,
			error = "profile has no authoritative captured texture hash",
		}
		Callback( callback, false, result )
		return false, result
	end

	-- Preview is permitted only when the provider advertised a reversible,
	-- reversible session overlay. Resolve its client-local draw identity here
	-- instead of ever doing so for a commit.
	Bridge.ResolveHashes( material, function( hashes, reason )
		if not ApplyIsCurrent( ApplyKey( operation, material ), generation ) then
			Superseded( callback )
			return
		end
		if #hashes == 0 then
			Callback( callback, false, {
				status = "waiting-for-hash", live = false, error = reason,
			} )
			return
		end
		NativeCall( operation, profile, compiled, hashes, callback )
	end )

	return nil, { status = "pending-hash", live = false }
end

local function ApplyNow( operation, profile, callback, generation, retried )
	local material = TargetMaterial( profile )
	if material == "" then
		local result = { status = "failed", live = false, error = "empty material" }
		Callback( callback, false, result )
		return false, result
	end
	if not ApplyIsCurrent( ApplyKey( operation, material ), generation ) then
		Superseded( callback )
		return false, { status = "superseded", live = false }
	end

	local compiled, compileError = Compile( profile )
	if not compiled then
		local result = { status = "failed", live = false, error = tostring( compileError ) }
		Callback( callback, false, result )
		return false, result
	end

	-- Export-only preview has no consumer and should not spend seconds baking a
	-- texture that cannot be displayed.  Commits are materialized for export;
	-- every native apply is materialized before crossing the writer boundary.
	if operation == "preview" and not Bridge.HasNativeWriter() then
		return NativeCall( operation, profile, compiled, Bridge.ResolveHashes( material ), callback )
	end

	local applyResult, applyDetail
	local materialized = MaterializeCompiled( compiled, function( ok, ready, reason )
		if not ApplyIsCurrent( ApplyKey( operation, material ), generation ) then
			Superseded( callback )
			return
		end
		if not ok then
			applyResult = false
			applyDetail = { status = "generation-failed", live = false, error = reason }
			Callback( callback, false, applyDetail )
			return
		end
		applyResult, applyDetail = ApplyCompiled( operation, profile, ready, function( applied, result )
			-- A map named straight from an enhancement mod that is a link to a
			-- folder outside the game: the writer only says so by refusing. The
			-- mod is remembered and the same apply goes again with stand-ins.
			local enhance = AdvMat.RTX.Enhance
			if not applied and not retried and enhance
				and enhance.NoteLinkedRefusal( ready, istable( result ) and result.error or nil ) then
				ApplyNow( operation, profile, callback, generation, true )
				return
			end
			Callback( callback, applied, result )
		end, generation )
	end )

	if materialized == nil then
		return nil, { status = "generating", live = false }
	end
	return applyResult, applyDetail
end

local function QueueApply( operation, profile, callback, delay )
	local material = TargetMaterial( profile )
	if material == "" then
		Callback( callback, false, { status = "failed", error = "empty material", live = false } )
		return false
	end

	local key = ApplyKey( operation, material )
	local previous = Bridge.ApplyQueue[ key ]
	if previous and previous.callback ~= callback then
		Callback( previous.callback, false, { status = "superseded", live = false } )
	end

	Bridge.ApplySerial = ( tonumber( Bridge.ApplySerial ) or 0 ) + 1
	local generation = Bridge.ApplySerial
	Bridge.ApplyGeneration[ key ] = generation
	local queued = {
		operation = operation, profile = Copy( profile ), callback = callback,
		generation = generation,
	}
	Bridge.ApplyQueue[ key ] = queued

	local timerName = "AdvMat.RTX.Apply." .. util.CRC( key )
	-- Throttle previews rather than restarting a trailing debounce forever
	-- while a slider is dragged. The pending tick reads the latest value.
	if operation == "preview" and timer.Exists( timerName ) then
		return true, { status = "queued", live = false }
	end
	timer.Create( timerName, delay, 1, function()
		local latest = Bridge.ApplyQueue[ key ]
		if not latest then return end
		Bridge.ApplyQueue[ key ] = nil
		ApplyNow( operation, latest.profile, latest.callback, latest.generation )
	end )

	return true, { status = "queued", live = false }
end

function Bridge.Preview( profile, callback )
	local caps = Bridge.Capabilities()
	if caps.livePreview ~= true then
		local result = {
			status = "preview-unavailable",
			live = false,
			exportOnly = caps.exportOnly == true,
			error = "the installed RTX writer does not provide a reversible preview layer",
		}
		Callback( callback, false, result )
		return false, result
	end
	return QueueApply( "preview", profile, callback, PREVIEW_DEBOUNCE )
end

function Bridge.Commit( profile, callback )
	return QueueApply( "commit", profile, callback, COMMIT_DEBOUNCE )
end

local function CancelApply( key )
	local previous = Bridge.ApplyQueue[ key ]
	Bridge.ApplyQueue[ key ] = nil
	timer.Remove( "AdvMat.RTX.Apply." .. util.CRC( key ) )
	Bridge.ApplySerial = ( tonumber( Bridge.ApplySerial ) or 0 ) + 1
	Bridge.ApplyGeneration[ key ] = Bridge.ApplySerial
	if previous then Superseded( previous.callback ) end
end

function Bridge.RestorePreview( material, callback )
	material = TargetMaterial( material )
	if material == "" then return false end
	local key = ApplyKey( "preview", material )
	CancelApply( key )
	local generation = Bridge.ApplyGeneration[ key ]
	local provider, caps = WriterProvider()
	if not provider or caps.reversiblePreview ~= true or not isfunction( provider.RestorePreview ) then
		Callback( callback, false, { status = "preview-unavailable", live = false } )
		return false
	end
	local function Attempt( remaining )
		if not ApplyIsCurrent( key, generation ) then Superseded( callback ) return false end
		local ok, accepted, detail = pcall( provider.RestorePreview, {
			protocol = Bridge.CONTRACT_VERSION, target = { material = material },
		} )
		local success = ok and accepted == true
		local result = success and { status = "preview-restored", live = true }
			or { status = "failed", live = false, error = tostring( ok and detail or accepted ) }
		if not success and remaining > 0 then
			timer.Simple( 0.5, function() Attempt( remaining - 1 ) end )
			return nil, { status = "restoring", live = false }
		end
		if not success and AdvMat.NotifyLocal then
			AdvMat.NotifyLocal( AdvMat.L( "rtx.preview_restore_failed", { error = result.error } ), 1, 8 )
		end
		Callback( callback, success, result )
		return success, result
	end
	return Attempt( 2 )
end

--- Remove the writer-owned layer for a recorded target.  Clear is keyed by
--- the stable material/profile identity, so it must not wait for the material
--- to render again.  When the authoritative store retained captured hashes in
--- a tombstone, forward those exact string identities as an additional guard
--- instead of re-resolving whatever happens to be visible now.
function Bridge.RestoreTarget( target, callback )
	local source = istable( target ) and ( target.target or target ) or {}
	local material = TargetMaterial( target )
	if material == "" then
		Callback( callback, false, { status = "failed", error = "empty material", live = false } )
		return false
	end
	local hashes = NormalizeHashes( source.hashes
		or ( source.hash and { source.hash } ) or {} )

	CancelApply( material )
	CancelApply( ApplyKey( "preview", material ) )

	local provider, capsOrError = WriterProvider()
	if not provider then
		if rawget( _G, "AdvMatRTXBridge" ) ~= nil then
			local result = {
				status = "native-blocked", live = false, exportOnly = false,
				error = tostring( capsOrError or "native writer failed its authoritative reset" ),
			}
			Callback( callback, false, result )
			return false, result
		end
		-- There is no live state to restore, but an earlier export must not remain
		-- as a stale instruction for a runtime-side importer after the profile is
		-- cleared.
		local path = Bridge.ExportFolder .. "/" .. ExportFileName( material )
		local removed, removeError = RemoveDataFile( path )
		if not removed then
			local result = {
				status = "failed", live = false, exportOnly = true,
				path = path, error = "could not remove RTX export: " .. tostring( removeError ),
			}
			Callback( callback, false, result )
			return false, result
		end
		Bridge.LastExport[ material ] = nil
		local result = {
			status = "export-removed", live = false, exportOnly = true,
			path = path, error = capsOrError,
		}
		Callback( callback, true, result )
		return true, result
	end

	local request = {
		protocol = Bridge.CONTRACT_VERSION,
		operation = "restore",
		target = { material = material },
		hashes = Copy( hashes ),
	}
	local ok, accepted, detail = pcall( provider.ClearLegacyMaterial, request )
	if not ok or accepted ~= true then
		local result = { status = "failed", live = false,
			error = tostring( ok and detail or accepted ) }
		Callback( callback, false, result )
		return false, result
	end

	local result = istable( detail ) and detail or {}
	result.status = result.status or "restored"
	result.live = true
	result.capabilities = Copy( capsOrError )
	Callback( callback, true, result )
	return true, result
end

function Bridge.Restore( material, callback )
	return Bridge.RestoreTarget( { material = TargetMaterial( material ) }, callback )
end

--- Inspect Source metadata and captured hashes without changing anything.
function Bridge.Inspect( material, callback )
	material = TargetMaterial( material )
	local result = {
		material     = material,
		hashes       = {},
		source       = nil,
		capabilities = Bridge.Capabilities(),
	}

	local pipeline = PipelineTable()
	if pipeline and isfunction( pipeline.InspectMaterial ) and material ~= "" then
		local ok, inspected = pcall( pipeline.InspectMaterial, material )
		if ok and istable( inspected ) then
			result.source = inspected
		elseif not ok then
			result.inspectError = tostring( inspected )
		end
	end

	result.hashes = Bridge.ResolveHashes( material, isfunction( callback ) and function( hashes, reason )
		result.hashes = hashes
		result.hashError = reason
		Callback( callback, Copy( result ) )
	end or nil )

	return result
end
