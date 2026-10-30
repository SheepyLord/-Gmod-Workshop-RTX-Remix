--[[---------------------------------------------------------------------------
	Advanced Material Editor - shared configuration & constants
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

---------------------------------------------------------------------------
-- Notification kinds
---------------------------------------------------------------------------
-- The NOTIFY_* enums are clientside-only engine globals, but the server needs
-- them too: every AdvMat.Notify call in sv_* and in the serverside half of the
-- tool passes one, and a nil there makes net.WriteUInt throw mid-message --
-- which both loses the notification and leaves the net message dangling until
-- the next net.Start discards it. Written with `or` so the client keeps the
-- engine's own values.
NOTIFY_GENERIC = NOTIFY_GENERIC or 0
NOTIFY_ERROR   = NOTIFY_ERROR   or 1
NOTIFY_UNDO    = NOTIFY_UNDO    or 2
NOTIFY_HINT    = NOTIFY_HINT    or 3
NOTIFY_CLEANUP = NOTIFY_CLEANUP or 4

---------------------------------------------------------------------------
-- Rule scopes
---------------------------------------------------------------------------
-- ENTITY   : applies to one specific entity. Survives duplication and
--            map save/load via a duplicator entity modifier.
-- MODEL    : applies to submaterial <index> of every entity using <model>.
--            Persisted to disk; this is what makes an edit "stick" forever.
-- MATERIAL : applies to any submaterial slot whose VMT path is <material>,
--            on any model. Persisted to disk. Broadest scope.
-- WORLD  : applies to a map surface material. Brush geometry has no
--          sub-material slots for SetSubMaterial to reach, so these are
--          applied by editing the shared material itself, clientside. See
--          the world section of cl_50_apply.lua.
AdvMat.SCOPE = {
	ENTITY   = 1,
	MODEL    = 2,
	MATERIAL = 3,
	WORLD    = 4,
}

AdvMat.SCOPE_NAME = {
	[ AdvMat.SCOPE.ENTITY   ] = "This entity only",
	[ AdvMat.SCOPE.MODEL    ] = "Every prop with this model",
	[ AdvMat.SCOPE.MATERIAL ] = "Every material with this path",
	[ AdvMat.SCOPE.WORLD    ] = "This map surface material",
}

AdvMat.SCOPE_SHORT = {
	[ AdvMat.SCOPE.ENTITY   ] = "entity",
	[ AdvMat.SCOPE.MODEL    ] = "model",
	[ AdvMat.SCOPE.MATERIAL ] = "material",
	[ AdvMat.SCOPE.WORLD    ] = "world",
}

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
AdvMat.DataFolder = "advmat"
AdvMat.DataFile   = "advmat/overrides.json"

-- Source engine hard limit on submaterials per model.
AdvMat.MAX_SUBMATERIALS = 32

---------------------------------------------------------------------------
-- Convars
---------------------------------------------------------------------------
-- Replicated, so the client can see which application mode is in force.
-- 1 : the server applies saved overrides with Entity:SetSubMaterial. They are
--     durable, survive an entity leaving and re-entering the PVS, and every
--     player sees them. Each distinct material name costs one slot in the
--     shared network string table.
-- 0 : each client applies its own copy. Nothing is networked and no network
--     strings are used, but the client has to keep re-applying, and players
--     without the addon see nothing.
CreateConVar( "advmat_serverside", "1", { FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"1 = the server applies material overrides (durable, everyone sees them). 0 = each client applies its own." )

if SERVER then
	CreateConVar( "advmat_enabled", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
		"Enable the Advanced Material Editor tool." )

	CreateConVar( "advmat_adminonly", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
		"Only admins may save persistent material overrides. 0 = everyone." )

	-- Kept well below the network string table's capacity, which is shared
	-- with every other addon on the server.
	CreateConVar( "advmat_max_rules", "512", { FCVAR_ARCHIVE },
		"Maximum number of persistent override rules kept on disk." )

	CreateConVar( "advmat_autosave", "1", { FCVAR_ARCHIVE },
		"Write the override database to disk immediately after every change." )
end

if CLIENT then
	-- Every pixel of a generated texture is a Lua table entry, because there is
	-- no image API to hand the work to. That makes resolution a real cost
	-- rather than a preference: 1024 is unremarkable, while 4096 x 4096 is
	-- sixteen million entries across four arrays - a few hundred megabytes and
	-- a pause of several seconds.
	--
	-- So the ceiling is a setting, and it defaults to what the editor could do
	-- before larger textures were supported at all. Somebody working on a 4096
	-- character sheet raises it deliberately; nobody meets the cost by accident.
	--
	-- It governs what this client OFFERS and defaults to. It deliberately does
	-- not reject a rule that already asks for more: rules are shared, and
	-- refusing to build one at the size it names would show this player a
	-- different material from everybody else.
	CreateConVar( "advmat_max_texture_size", "1024", { FCVAR_ARCHIVE },
		"Largest texture the editor will read or generate. Bigger costs time and memory." )
end

---------------------------------------------------------------------------
-- Shared helpers used everywhere
---------------------------------------------------------------------------
function AdvMat.IsAllowed( ply )
	if not IsValid( ply ) then return false end
	if not GetConVar( "advmat_enabled" ):GetBool() then return false end
	if not GetConVar( "advmat_adminonly" ):GetBool() then return true end
	return ply:IsAdmin()
end

function AdvMat.Log( fmt, ... )
	MsgC( Color( 120, 200, 255 ), "[AdvMat] ", Color( 220, 220, 220 ),
		string.format( fmt, ... ), "\n" )
end
