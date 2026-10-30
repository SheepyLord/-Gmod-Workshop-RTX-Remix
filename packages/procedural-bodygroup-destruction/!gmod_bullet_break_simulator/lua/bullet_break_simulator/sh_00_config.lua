-- Shared configuration and small debug helpers.

BBS = BBS or {}

BBS.NET_HIT = "BBS.RagdollHit"
BBS.NET_SET_ENABLED = "BBS.SetEnabled"
BBS.NET_SET_DEATH_ONLY = "BBS.SetDeathRagdollsOnly"
BBS.NET_SET_LIVING_PLAYERS = "BBS.SetLivingPlayers"
BBS.NET_SET_LIVING_NPCS = "BBS.SetLivingNPCs"
BBS.NET_TRANSFER_DEATH_DAMAGE = "BBS.TransferDeathDamage"

if SERVER then
	CreateConVar( "bbs_enabled", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
		"Enable Procedural Bodygroup Destruction bullet-hit detection and material damage." )
	local livingPlayers = CreateConVar( "bbs_damage_living_players", "1",
		{ FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
		"Apply Procedural Bodygroup Destruction effects to living players." )
	local livingNPCs = CreateConVar( "bbs_damage_living_npcs", "1",
		{ FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
		"Apply Procedural Bodygroup Destruction effects to living NPCs." )
	CreateConVar( "bbs_death_ragdolls_only", "1",
		{ FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
		"Apply the effect only to server ragdolls created from NPCs or players." )

	local serverLogging = CreateConVar( "bbs_server_logging", "0", { FCVAR_ARCHIVE },
		"Print detected ragdoll bullet hits in the server console." )
	local serverSettingsRevision = CreateConVar( "bbs_server_settings_revision", "0",
		{ FCVAR_ARCHIVE }, "Internal version for one-time server default migrations." )
	timer.Simple( 0, function()
		local previousRevision = serverSettingsRevision:GetInt()
		if previousRevision < 1 then serverLogging:SetBool( false ) end
		-- Revision 2 makes both living-target modes part of the normal first-run
		-- experience. Apply it once to existing 0.16.0 installs as well; later
		-- user choices remain archived and are not overwritten on every launch.
		if previousRevision < 2 then
			livingPlayers:SetBool( true )
			livingNPCs:SetBool( true )
			serverSettingsRevision:SetInt( 2 )
		end
	end )
end

local function SharedConVarBool( name, fallback )
	local convar = GetConVar( name )
	if not convar then return fallback end
	return convar:GetBool()
end

function BBS.GetDamageTargetKind( entity )
	if not IsValid( entity ) then return nil end
	if entity:GetClass() == "prop_ragdoll" then return "ragdoll" end
	if entity:IsPlayer() then return "player" end
	if entity:IsNPC() or hook.Run( "BBS.IsLivingNPCTarget", entity ) == true then return "npc" end
	return nil
end

-- Opt-in adapters let a scripted actor participate without changing IsNPC for
-- every addon or automatically treating all NextBots as humanoid targets.
function BBS.IsLivingDamageTarget( entity )
	local kind = BBS.GetDamageTargetKind( entity )
	return kind == "npc" or kind == "player"
end

-- This policy is shared by the server detector and every asynchronous client
-- stage. Rechecking it before dispatch and material application ensures a menu
-- toggle takes effect even when a hit was already waiting in a burst/cache job.
function BBS.IsDamageTargetEnabled( entity )
	local kind = BBS.GetDamageTargetKind( entity )
	if not kind then return false, nil, "unsupported entity type" end
	if not SharedConVarBool( "bbs_enabled", true ) then
		return false, kind, "addon is disabled"
	end
	if kind == "ragdoll" then return true, kind, "ragdoll effects enabled" end
	if kind == "player" then
		if not SharedConVarBool( "bbs_damage_living_players", true ) then
			return false, kind, "living-player effects are disabled"
		end
		return true, kind, "living-player effects enabled"
	end
	if not SharedConVarBool( "bbs_damage_living_npcs", true ) then
		return false, kind, "living-NPC effects are disabled"
	end
	return true, kind, "living-NPC effects enabled"
end

-- Keep RTX detection dynamic: Remix's native bridge and its Lua wrappers can
-- appear after this addon during client startup.  The broad probe preserves the
-- existing material-compatibility behaviour, while the strict probe is used by
-- scheduling and memory policy so merely mounting Remix's Lua files in vanilla
-- Garry's Mod can never change the normal-game workload.
function BBS.GetRTXRemixDetectionReason()
	if not CLIENT then return nil end
	if isfunction( _G.RTX_ReloadModelsAfterHardwareSkinningSettings ) then
		return "hardware-skinning reload hook"
	end
	if istable( _G.RTXMaterialPipeline ) then return "RTXMaterialPipeline" end
	if GetConVar( "r_remix_material_debug" ) then
		return "r_remix_material_debug"
	end
	if GetConVar( "rtx_mat_enabled" ) and GetConVar( "r_forcehwskin" ) then
		return "RTX material/hardware-skinning convars"
	end
	return nil
end

function BBS.IsRTXRemixClient()
	return BBS.GetRTXRemixDetectionReason() ~= nil
end

function BBS.GetActiveRTXRuntimeReason()
	if not CLIENT then return nil end
	if GetConVar( "r_remix_material_debug" ) then
		return "native Remix render convar"
	end
	if isfunction( _G.RTX_ReloadModelsAfterHardwareSkinningSettings ) then
		return "native hardware-skinning bridge"
	end
	local pipeline = _G.RTXMaterialPipeline
	if istable( pipeline ) and isfunction( pipeline.IsAvailable ) then
		local ok, available = pcall( pipeline.IsAvailable )
		if ok and available then return "active RTX material pipeline" end
	end
	local config, material = _G.RemixConfig, _G.RemixMaterial
	if istable( config ) and isfunction( config.GetConfigVariable )
	and istable( material )
	and ( isfunction( material.GetTextureHash )
		or isfunction( material.GetAllTextureHashes ) ) then
		return "native Remix configuration/material APIs"
	end
	return nil
end

function BBS.IsActiveRTXRuntime()
	return BBS.GetActiveRTXRuntimeReason() ~= nil
end

if CLIENT then
	CreateClientConVar( "bbs_debug_overlay", "0", true, false,
		"Draw the ragdoll bullet-hit debug overlay." )
	CreateClientConVar( "bbs_debug_console", "0", true, false,
		"Print detailed client hit and retrace diagnostics." )
	CreateClientConVar( "bbs_debug_hud", "0", true, false,
		"Show a compact last-hit status panel." )
	CreateClientConVar( "bbs_debug_labels", "0", true, false,
		"Draw labels beside 3D hit markers." )
	CreateClientConVar( "bbs_debug_through_walls", "1", true, false,
		"Draw hit markers through world geometry." )
	CreateClientConVar( "bbs_debug_duration", "15", true, false,
		"Seconds a marker remains. Zero keeps markers until cleared." )
	CreateClientConVar( "bbs_debug_size", "3", true, false,
		"World-space debug marker size." )
	CreateClientConVar( "bbs_debug_trace_length", "32", true, false,
		"Distance traced on each side of the reported damage position." )
	CreateClientConVar( "bbs_debug_max_markers", "64", true, false,
		"Maximum number of debug hits retained on this client." )
	CreateClientConVar( "bbs_hull_enabled", "0", true, false,
		"Draw the irregular removal hull at refined ragdoll hits." )
	CreateClientConVar( "bbs_hull_radius", "0.5", true, false,
		"Removal hull radius in world units." )
	CreateClientConVar( "bbs_hull_inside_distance", "4", true, false,
		"Removal hull distance extending into the ragdoll along the hit direction." )
	CreateClientConVar( "bbs_hull_outside_distance", "10", true, false,
		"Removal hull distance extending outside the ragdoll against the hit direction." )
	CreateClientConVar( "bbs_hull_segments", "20", true, false,
		"Number of radial segments used to draw the removal hull." )
	CreateClientConVar( "bbs_hull_fill_alpha", "38", true, false,
		"Removal hull translucent fill alpha (0..255)." )
	CreateClientConVar( "bbs_hole_damage_scaling", "1", true, false,
		"Scale removal-hull size and edge damage from bullet damage." )
	CreateClientConVar( "bbs_hole_reference_damage", "5", true, false,
		"Bullet damage which produces the configured base removal-hull radius." )
	CreateClientConVar( "bbs_hole_max_radius_multiplier", "5", true, false,
		"Hard upper cap for damage-scaled removal-hull radius, relative to the base radius." )
	CreateClientConVar( "bbs_hole_base_irregularity", "0.4", true, false,
		"Base amount of deterministic tearing and edge irregularity." )
	CreateClientConVar( "bbs_hole_damage_irregularity", "0.5", true, false,
		"Additional edge irregularity per damage radius multiplier above one." )
	CreateClientConVar( "bbs_hole_max_irregularity", "0.9", true, false,
		"Hard upper cap for damage-scaled edge irregularity." )
	CreateClientConVar( "bbs_hole_shape_samples", "24", true, false,
		"Number of deterministic polar boundary samples used by irregular bullet holes." )
	-- Keep the baseline at 15 so revision 16's targeted migration also sees
	-- older configs which archived softness but omitted the old default revision.
	CreateClientConVar( "bbs_settings_revision", "15", true, false,
		"Internal version for one-time default setting migrations." )
	CreateClientConVar( "bbs_mesh_query_budget_ms", "10", true, false,
		"Maximum client frame time spent on asynchronous mesh queries." )
	CreateClientConVar( "bbs_mesh_build_budget_ms", "15", true, false,
		"Maximum client frame time spent packing a cold model mesh cache after native extraction." )
	CreateClientConVar( "bbs_mesh_prepare_target_seconds", "2", true, false,
		"Soft wall-time target used for cache-preparation diagnostics." )
	CreateClientConVar( "bbs_mesh_prepare_catchup_ms", "20", true, false,
		"Absolute cache-preparation slice cap; the scheduler never exceeds this to chase a wall-time target." )
	CreateClientConVar( "bbs_mesh_rtx_background_budget_ms", "15", true, false,
		"RTX-only ceiling for speculative cache preparation; vanilla Garry's Mod never reads this budget." )
	CreateClientConVar( "bbs_mesh_rtx_catchup_ms", "25", true, false,
		"RTX-only urgent cache-preparation ceiling at 60 FPS or above; it falls back toward the normal cap at low FPS." )
	CreateClientConVar( "bbs_mesh_prewarm", "1", true, false,
		"Build model mesh caches shortly after a ragdoll appears instead of on its first hit." )
	CreateClientConVar( "bbs_mesh_prewarm_living", "1", true, false,
		"Prewarm NPC and player models before they become death ragdolls." )
	CreateClientConVar( "bbs_mesh_disk_cache", "1", true, false,
		"Persist processed model mesh caches in data/bbs_mesh_cache across restarts." )
	CreateClientConVar( "bbs_mesh_cache_io_budget_ms", "10", true, false,
		"Maximum background time per frame for persistent mesh-cache hydration and writes." )
	CreateClientConVar( "bbs_mesh_cache_write_limit", "3", true, false,
		"Maximum full processed-model graphs retained by pending persistent-cache writes." )
	CreateClientConVar( "bbs_mesh_cache_max_entries", "6", true, false,
		"Maximum processed model variants retained in Lua memory; zero is unlimited." )
	CreateClientConVar( "bbs_mesh_cache_max_triangles", "350000", true, false,
		"Approximate triangle budget for processed model caches in Lua memory; zero is unlimited." )
	CreateClientConVar( "bbs_mesh_candidate_padding", "2", true, false,
		"Extra bone-local padding used by the conservative triangle candidate filter." )
	CreateClientConVar( "bbs_mesh_restrict_to_hideable", "1", true, false,
		"When cached, query only meshes proven to belong to blank-capable bodygroups." )
	CreateClientConVar( "bbs_mesh_force_full_scan", "0", true, false,
		"Disable bone-local acceleration and scan every eligible model triangle." )
	CreateClientConVar( "bbs_mesh_local_bounds", "1", true, false,
		"Use conservative removal-hull-local interval bounds before exact triangle tests." )
	CreateClientConVar( "bbs_hit_coalesce", "1", true, false,
		"Cluster simultaneous pellet impacts before running mesh and material analysis." )
	CreateClientConVar( "bbs_hit_coalesce_window", "0.04", true, false,
		"Seconds used to collect a burst of simultaneous impacts." )
	CreateClientConVar( "bbs_hit_coalesce_radius", "3", true, false,
		"World-space distance within which burst impacts merge into one tear." )
	CreateClientConVar( "bbs_hit_coalesce_max_clusters", "4", true, false,
		"Maximum spatial tear jobs retained for one entity in a simultaneous burst." )
	CreateClientConVar( "bbs_hit_dispatch_per_frame", "1", true, false,
		"Maximum completed burst clusters entering the expensive hit pipeline each frame." )
	CreateClientConVar( "bbs_hit_queue_limit", "32", true, false,
		"Soft pending-burst watermark; excess same-target work is coalesced without dropping damage." )
	CreateClientConVar( "bbs_deferred_hit_limit", "4", true, false,
		"Soft diagnostic watermark for pose snapshots waiting on cold model caches; snapshots are not time-expired." )
	CreateClientConVar( "bbs_damage_enabled", "1", true, false,
		"Apply UV transparency damage to meshes belonging to blank-capable bodygroups." )
	CreateClientConVar( "bbs_damage_apply_materials", "1", true, false,
		"Create and apply transparent material overrides after UV retrieval." )
	CreateClientConVar( "bbs_damage_layer_limit", "0", true, false,
		"Maximum visual mesh-surface layers affected by one ray; zero is unlimited." )
	CreateClientConVar( "bbs_damage_force_nocull", "1", true, false,
		"Force $nocull 1 on generated damage materials so torn openings show back faces." )
	CreateClientConVar( "bbs_damage_rtx_direct_override", "1", true, false,
		"On RTX Remix, bind damaged materials directly while drawing affected ragdolls." )
	CreateClientConVar( "bbs_damage_rt_size", "2048", true, false,
		"Legacy compatibility setting; ignored. Damage targets always use full source texture resolution." )
	CreateClientConVar( "bbs_damage_coverage_rt_size", "1024", true, false,
		"Legacy compatibility setting; ignored. Coverage always uses full source texture resolution." )
	CreateClientConVar( "bbs_damage_uv_expand_pixels", "1", true, false,
		"Outward expansion of selected UV triangles in render-target pixels." )
	CreateClientConVar( "bbs_damage_uv_feather_pixels", "0", true, false,
		"Blur radius applied to a hit's temporary UV coverage mask." )
	CreateClientConVar( "bbs_damage_uv_blur_passes", "2", true, false,
		"Number of blur passes applied to a hit's UV coverage mask." )
	CreateClientConVar( "bbs_damage_uv_unwrap_seams", "1", true, false,
		"Unwrap triangle UV coordinates across integer texture seams before rasterizing." )
	CreateClientConVar( "bbs_damage_projection_depth", "4", true, false,
		"Maximum adaptive subdivision depth for projecting the finite cylinder into UV space." )
	CreateClientConVar( "bbs_damage_projection_tolerance", "0.04", true, false,
		"World-space boundary tolerance for adaptive cylinder projection." )
	CreateClientConVar( "bbs_damage_projection_max_triangles", "16384", true, false,
		"Safety cap for projected UV micro-triangles generated by one affected material." )
	CreateClientConVar( "bbs_damage_projection_budget_ms", "6.25", true, false,
		"Maximum client frame time spent projecting one material's removal hull into UV space." )
	CreateClientConVar( "bbs_damage_projection_local_bounds", "1", true, false,
		"Use angle-aware conservative bounds while projecting irregular hulls into UV space." )
	CreateClientConVar( "bbs_damage_batch_raster", "0", true, false,
		"Experimental: batch projected UV coverage into dynamic meshes instead of surface polygons." )
	CreateClientConVar( "bbs_damage_uv_preview", "0", true, false,
		"Show the most recently affected material and selected UV triangles." )
	CreateClientConVar( "bbs_damage_uv_console_limit", "24", true, false,
		"Maximum unique UV coordinates printed per affected mesh." )
	CreateClientConVar( "bbs_damage_dump_debug", "0", true, false,
		"Write human-readable material, hit, UV, and texture debug bundles to data/bbs_debug." )
	CreateClientConVar( "bbs_damage_validate_copy", "0", true, false,
		"Run a slow synchronous GPU pixel-readback after copying a source texture." )
	CreateClientConVar( "bbs_damage_print_vmt", "0", true, false,
		"Print the complete generated VMT after each material application." )
	CreateClientConVar( "bbs_damage_verbose_uv", "0", true, false,
		"Print individual affected UV coordinates for every hit." )
	CreateClientConVar( "bbs_perf_enabled", "0", true, false,
		"Record per-stage Procedural Bodygroup Destruction client CPU timings." )
	CreateClientConVar( "bbs_perf_hud", "0", true, false,
		"Draw the rolling Procedural Bodygroup Destruction performance report." )
	CreateClientConVar( "bbs_perf_console", "0", true, false,
		"Print a ranked performance report when a profiled hit finishes." )
	CreateClientConVar( "bbs_perf_history", "32", true, false,
		"Number of completed hit performance records retained for aggregate reporting." )
	CreateClientConVar( "bbs_perf_stage_limit", "8", true, false,
		"Maximum number of ranked stages shown in the performance HUD." )
end

function BBS.Log( fmt, ... )
	MsgC( Color( 255, 165, 70 ), "[BBS] ", Color( 225, 225, 225 ),
		string.format( fmt, ... ), "\n" )
end

function BBS.FormatVector( value )
	if not value then return "<nil>" end
	return string.format( "%.2f %.2f %.2f", value.x, value.y, value.z )
end
