--[[---------------------------------------------------------------------------
	Advanced Material Editor - backend dispatcher

	This is the only place where a tool click chooses an editor.  A session is
	frozen to one backend until its window closes: the Source/VMT editor never
	loads RTX controls into its rule path, and the RTX editor never calls the
	Source SetSubMaterial persistence path.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local function SessionMode( session )
	if isstring( session ) then return session end
	if istable( session ) then return session.mode or session.backend end
	return "vanilla"
end

local function FocusCurrentEditor()
	local editor = AdvMat.Editor
	if not IsValid( editor ) then return nil end

	local focus = editor
	for _, name in ipairs( {
		"TexPicker", "TexEditor", "SurfaceDialog", "GenDialog",
	} ) do
		local child = AdvMat[ name ]
		if IsValid( child ) and child.AdvMatHost == editor then
			focus = child
			break
		end
	end

	if AdvMat.WindowUX then
		AdvMat.WindowUX.Focus( focus )
	else
		if isfunction( focus.MakePopup ) then focus:MakePopup() end
		if isfunction( focus.MoveToFront ) then focus:MoveToFront() end
	end
	return editor
end

--- Public entry point used by the tool and by compatibility callers.
function AdvMat.OpenEditor( ent, worldMat )
	if not IsValid( ent ) and ( not worldMat or worldMat == "" ) then return end

	local current = FocusCurrentEditor()
	if current then return current end

	local session = { mode = "vanilla", requested = "auto" }
	if AdvMat.Backend and isfunction( AdvMat.Backend.BeginSession ) then
		local ok, selected = pcall( AdvMat.Backend.BeginSession, ent or worldMat )
		if ok and selected ~= nil then session = selected end
	end

	local mode = SessionMode( session )
	if mode == "rtx" and isfunction( AdvMat.OpenRTXEditor ) then
		return AdvMat.OpenRTXEditor( ent, worldMat, session )
	end

	-- A selected RTX session falls back only if its dedicated editor failed to
	-- register.  The normal path above supports both model and world materials.
	if mode == "rtx" and not isfunction( AdvMat.OpenRTXEditor ) then
		AdvMat.NotifyLocal(
			AdvMat.L and AdvMat.L( "notify.rtx_editor_fallback" )
				or "RTX Remix was detected, but its editor failed to load. Opening the vanilla editor.",
			NOTIFY_ERROR, 7 )
		-- The fallback window is a vanilla session in behavior as well as UI.
		-- Do not leave an RTX-mode snapshot attached to it, or background RTX
		-- handshakes could run for the lifetime of a Source/VMT editor.
		if istable( session ) then session.mode = "vanilla" end
	end

	if isfunction( AdvMat.OpenVanillaEditor ) then
		return AdvMat.OpenVanillaEditor( ent, worldMat, session )
	end
	if AdvMat.Backend and isfunction( AdvMat.Backend.EndSession ) then
		AdvMat.Backend.EndSession( session )
	end
end

net.Receive( "AdvMat.Open", function()
	local ent      = net.ReadEntity()
	local canWrite = net.ReadBool()
	local worldMat = net.ReadString()

	if not IsValid( ent ) and worldMat == "" then return end

	local frame = AdvMat.OpenEditor( ent, worldMat )
	if frame then frame.AdvMatCanWrite = canWrite end

	if frame and not canWrite then
		AdvMat.NotifyLocal(
			AdvMat.L and AdvMat.L( "notify.admin_save" )
				or "You can preview changes, but only admins can save them on this server.",
			NOTIFY_HINT, 6 )
	end
end )
