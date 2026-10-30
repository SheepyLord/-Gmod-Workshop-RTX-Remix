--[[---------------------------------------------------------------------------
	Advanced Material Editor - renderer backend selection

	The Source/VMT editor and the RTX Remix editor are deliberately separate
	products behind one tool entry point.  This file only decides which one a
	new editor session should use; it never loads an RTX module and never changes
	the behaviour of an editor session that is already open.

	`advmat_backend` accepts:

		auto     use RTX only when a known, callable Remix capability exists
		vanilla  always use the Source/VMT editor
		rtx      open the RTX editor even without a live writer (export mode)

	The result is snapshotted by BeginSession.  A late-loading Remix binary may
	change the next session, but cannot swap the implementation underneath an
	active window.
-----------------------------------------------------------------------------]]

AdvMat         = AdvMat or {}
AdvMat.Backend = AdvMat.Backend or {}

local Backend = AdvMat.Backend

Backend.MODES = {
	auto    = true,
	vanilla = true,
	rtx     = true,
}

Backend.ConVar = Backend.ConVar or CreateClientConVar(
	"advmat_backend",
	"auto",
	true,
	true,
	"Material editor renderer: auto, vanilla, or rtx. RTX is isolated from the Source/VMT editor."
)

local function Callable( owner, name )
	return istable( owner ) and isfunction( owner[ name ] )
end

local function RequestedMode()
	local cv = GetConVar( "advmat_backend" ) or Backend.ConVar
	local requested = cv and string.lower( string.Trim( cv:GetString() or "" ) ) or "auto"
	return Backend.MODES[ requested ] and requested or "auto"
end

--- Read live capabilities without requiring or initializing any client module.
--- A table merely existing is not sufficient: stale globals can survive Lua
--- autorefresh, so every capability is tied to the exact functions we call.
function Backend.Capabilities()
	local remix  = rawget( _G, "RemixMaterial" )
	local config = rawget( _G, "RemixConfig" )
	local pipe   = rawget( _G, "RTXMaterialPipeline" )
	local topbr  = rawget( _G, "MaterialPipeline" )
	local writer = rawget( _G, "AdvMatRTXBridge" )

	local track = Callable( remix, "TrackMaterial" )
		and ( Callable( remix, "GetAllTextureHashes" ) or Callable( remix, "GetTextureHash" ) )
	local pipeline = Callable( pipe, "ProcessMaterial" )
	local inspect  = istable( topbr ) and istable( topbr.ToPBR )
		and Callable( topbr.ToPBR, "InspectMaterial" )

	-- The Remix Lua tables may be present in an ordinary x86-64 launch.  A
	-- table/function probe alone therefore produces false positives.  The
	-- installed pinned client exposes a callable runtime signal through
	-- RemixConfig.GetUIState, but NONE/0 is also returned when its underlying
	-- Remix interface is absent.  Only a real Basic/Advanced state is evidence;
	-- an initialized ToPBR pipeline is the reliable hidden-UI fallback.
	local uiState, configReady = nil, false
	if Callable( config, "GetUIState" ) then
		local ok, state = pcall( config.GetUIState )
		if ok and isnumber( state ) and state == state then
			uiState = state
			local states = istable( config.UIState ) and config.UIState or {}
			local basic = tonumber( states.Basic ) or 1
			local advanced = tonumber( states.Advanced ) or 2
			configReady = state == basic or state == advanced
		end
	end

	local toPBRReady = false
	if istable( topbr ) and istable( topbr.ToPBR ) and Callable( topbr.ToPBR, "IsInitialized" ) then
		local ok, ready = pcall( topbr.ToPBR.IsInitialized )
		toPBRReady = ok and ready == true
	end
	local runtimeReady = configReady or toPBRReady

	-- The optional writer contract is versioned.  A future provider with a
	-- different ABI must not be invoked by this release by accident.
	local nativeWriter = istable( writer )
		and tonumber( writer.API_VERSION ) == 1
		and Callable( writer, "Capabilities" )
		and Callable( writer, "ApplyLegacyMaterial" )
		and Callable( writer, "ClearLegacyMaterial" )
		and Callable( writer, "ClearAllOwned" )

	return {
		remix            = runtimeReady,
		runtimeReady     = runtimeReady,
		uiState          = uiState,
		configReady      = configReady,
		toPBRReady       = toPBRReady,
		materialTracking = track,
		pipeline         = pipeline,
		inspect          = inspect,
		nativeWriter     = nativeWriter,
	}
end

function Backend.IsRTXCapable()
	return Backend.Capabilities().remix == true
end

function Backend.GetRequested()
	return RequestedMode()
end

--- Resolve a mode for a future session.  Explicit RTX remains available on a
--- stock client so material packages can be authored/exported for another
--- machine; `auto` never opts a stock client into RTX UI.
function Backend.Resolve( requested )
	requested = isstring( requested ) and string.lower( string.Trim( requested ) ) or RequestedMode()
	if not Backend.MODES[ requested ] then requested = "auto" end

	if requested == "auto" then
		return Backend.IsRTXCapable() and "rtx" or "vanilla"
	end

	return requested
end

function Backend.Current()
	return Backend.Resolve( RequestedMode() )
end

Backend.NextSessionID = tonumber( Backend.NextSessionID ) or 0

--- Freeze the backend decision and capability view for one editor window.
--- `owner` is informational and may be an entity, panel, or opaque token.
function Backend.BeginSession( owner )
	Backend.NextSessionID = Backend.NextSessionID + 1

	local requested = RequestedMode()
	local session = {
		id           = Backend.NextSessionID,
		owner        = owner,
		requested    = requested,
		mode         = Backend.Resolve( requested ),
		capabilities = Backend.Capabilities(),
		started      = RealTime(),
		closed       = false,
	}

	return session
end

function Backend.EndSession( session )
	if not istable( session ) then return end
	if session.closed then return end
	local previousMode = session.mode
	session.closed = true
	session.owner  = nil
	-- Publish the newly unfrozen resolved mode.  Forced RTX -> auto on a stock
	-- client remains RTX while its window is open, then must withdraw the server
	-- handshake as soon as that frozen session ends.
	hook.Run( "AdvMatBackendSessionEnded", previousMode, Backend.Current() )
end

function Backend.SessionMode( session )
	if istable( session ) and not session.closed and Backend.MODES[ session.mode ] then
		return session.mode
	end
	return Backend.Current()
end

-- Modules supplied by the client can appear after InitPostEntity.  Consumers
-- that show a capability badge may listen for this hook; active sessions keep
-- their own snapshot and intentionally ignore it.
local lastSignature
local function CapabilitySignature()
	local c = Backend.Capabilities()
	return table.concat( {
		c.remix and "1" or "0",
		c.configReady and "1" or "0",
		c.toPBRReady and "1" or "0",
		c.materialTracking and "1" or "0",
		c.pipeline and "1" or "0",
		c.inspect and "1" or "0",
		c.nativeWriter and "1" or "0",
	}, ":" )
end

function Backend.PollCapabilities()
	local current = CapabilitySignature()
	if lastSignature == current then return end
	local previous = lastSignature
	lastSignature = current
	hook.Run( "AdvMatBackendCapabilitiesChanged", Backend.Capabilities(), previous )
end

hook.Add( "InitPostEntity", "AdvMat.BackendDetect", function()
	Backend.PollCapabilities()
	timer.Create( "AdvMat.BackendDetect", 2, 0, Backend.PollCapabilities )
end )

-- Explicit namespace assignments keep static API audits aware of methods
-- defined through the local Backend alias above.
AdvMat.Backend.BeginSession = Backend.BeginSession
AdvMat.Backend.Current = Backend.Current
AdvMat.Backend.IsRTXCapable = Backend.IsRTXCapable
AdvMat.Backend.EndSession = Backend.EndSession
