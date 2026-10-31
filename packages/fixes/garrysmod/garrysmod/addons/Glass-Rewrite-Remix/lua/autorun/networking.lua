AddCSLuaFile()

local generateUV, generateNormals, simplify_vertices, split_convex = include("world_functions.lua")

// networking
if SERVER then
    util.AddNetworkString("SHARD_NETWORK")
    util.AddNetworkString("GLASS_SHOW_CRACKS")
    util.AddNetworkString("GLASS_NO_COLLIDE")

    -- Track player interactions with physics objects for better collision detection
    local function TrackPlayerInteraction(ply, ent)
        if ent and ent:IsValid() and ent:GetPhysicsObject():IsValid() then
            ent.last_player_touch = {
                player = ply,
                time = CurTime()
            }
        end
    end
    hook.Add("PlayerUse", "glass_track_player_use", TrackPlayerInteraction)
    hook.Add("PhysgunPickup", "glass_track_physgun", TrackPlayerInteraction)

    -- Bound every packet, including a late join after many map windows have shattered.
    local MAX_SHARD_BYTES = 60000
    local function shardBytes(shard)
        if not IsValid(shard) or not shard.TRIANGLES or #shard.TRIANGLES == 0 then return end
        local bytes = 4 + #shard.TRIANGLES * 12
        if bytes + 8 > MAX_SHARD_BYTES then return end
        return bytes
    end
    local function writeShard(shard)
        net.WriteUInt(shard:EntIndex(), 16)
        net.WriteUInt(#shard.TRIANGLES, 16)
        for _, tri in ipairs(shard.TRIANGLES) do
            local pos = tri.pos
            net.WriteFloat(pos.x)
            net.WriteFloat(pos.y)
            net.WriteFloat(pos.z)
        end
    end
    local function sendBatch(batch, ply)
        if #batch == 0 then return end
        net.Start("SHARD_NETWORK")
        net.WriteBool(true)
        net.WriteUInt(#batch, 16)
        for _, shard in ipairs(batch) do writeShard(shard) end
        net.Send(ply)
    end

    -- Handles requests for shard data from clients
    net.Receive("SHARD_NETWORK", function(len, ply)
        -- If len > 0, client is requesting a single shard (post-break)
        if len > 0 then
            local shard = net.ReadEntity()
            if not shardBytes(shard) then return end
            
            net.Start("SHARD_NETWORK")
            net.WriteBool(false) -- Indicate this is NOT a full update
            writeShard(shard)
            net.Send(ply)
        else 
            -- If len == 0, client is joining and needs all existing shards
            local all_shards = ents.FindByClass("procedural_shard")
            local batch, bytes = {}, 8
            for _, shard in ipairs(all_shards) do
                local size = shardBytes(shard)
                if size then
                    if bytes + size > MAX_SHARD_BYTES then
                        sendBatch(batch, ply)
                        batch, bytes = {}, 8
                    end
                    batch[#batch + 1] = shard
                    bytes = bytes + size
                end
            end
            sendBatch(batch, ply)
        end
    end)
else
    local default_mat = Material("models/props_combine/health_charger_glass")

    -- With queued rendering (mat_queue_mode 2) the material system draws a frame on its own thread
    -- after Lua has moved on, so a mesh destroyed or rebuilt while such a frame still uses it is freed
    -- under the render thread: breaking any glass crashed the game in studiorender (review R4). Meshes
    -- are retired instead and destroyed several frames later.
    local retired = {}
    function GlassRewriteRetireMesh(mesh)
        if mesh and mesh.IsValid and mesh:IsValid() then
            retired[#retired + 1] = {mesh = mesh, frame = FrameNumber() + 8}
        end
    end
    hook.Add("Think", "glass_retired_meshes", function()
        if #retired == 0 then return end
        local frame = FrameNumber()
        for i = #retired, 1, -1 do
            local item = retired[i]
            if frame >= item.frame then
                if item.mesh:IsValid() then item.mesh:Destroy() end
                table.remove(retired, i)
            end
        end
    end)
    -- NEW: Receive finalized vertex data and build the visual mesh
    net.Receive("SHARD_NETWORK", function(len)
        local is_full_update = net.ReadBool()

        if is_full_update then
            -- This is a full update for a joining player
            local total_shards = net.ReadUInt(16)
            for i = 1, total_shards do
                local shard_index = net.ReadUInt(16)
                local vertex_count = net.ReadUInt(16)
                if shard_index > 0 and vertex_count > 0 then
                    ProcessShardData(shard_index, vertex_count)
                end
            end
        else
            -- This is an update for a single, newly-created shard
            local shard_index = net.ReadUInt(16)
            local vertex_count = net.ReadUInt(16)
            if shard_index > 0 and vertex_count > 0 then
                ProcessShardData(shard_index, vertex_count)
            end
        end
    end)

    -- Helper function to process received shard data and build the mesh
    function ProcessShardData(shard_index, vertex_count)
        local model_triangles = {}
        for i = 1, vertex_count do
            local pos_x = net.ReadFloat()
            local pos_y = net.ReadFloat()
            local pos_z = net.ReadFloat()
            
            -- Reconstruct the vertex table structure
            model_triangles[i] = { pos = Vector(pos_x, pos_y, pos_z) }
        end

        -- Try and find shard on client.
        -- Using timer.Simple(0,...) schedules this for the next frame,
        -- which is much faster than the old timer.Create and removes the artificial delay.
        timer.Simple(0, function()
            local shard_entity = Entity(shard_index)
            if not shard_entity:IsValid() then return end
            
            -- We have the exact triangles, no need to do any splitting
            shard_entity.TRIANGLES = model_triangles

            -- generate missing normals and uvs
            generateUV(shard_entity.TRIANGLES, -1/50)
            generateNormals(shard_entity.TRIANGLES)

            -- Build the visual mesh, guarding against race conditions where the entity
            -- exists but has not been fully initialized on the client yet.
            if not shard_entity.RENDER_MESH then
                shard_entity.RENDER_MESH = { Material = default_mat }
            end

            -- Build the new mesh before it replaces the old one, which may still be queued for drawing.
            local fresh = Mesh()
            fresh:BuildFromTriangles(shard_entity.TRIANGLES)
            local old = shard_entity.RENDER_MESH.Mesh
            shard_entity.RENDER_MESH.Mesh = fresh
            GlassRewriteRetireMesh(old)
            -- Map fragments have arbitrary dimensions, not the placeholder model's bounds.
            local low, high = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
            for _, vertex in ipairs(model_triangles) do
                local pos = vertex.pos
                low.x, low.y, low.z = math.min(low.x, pos.x), math.min(low.y, pos.y), math.min(low.z, pos.z)
                high.x, high.y, high.z = math.max(high.x, pos.x), math.max(high.y, pos.y), math.max(high.z, pos.z)
            end
            shard_entity:SetRenderBounds(low, high)

            -- Hide the original reference shard if it exists
            local reference_shard = shard_entity:GetReferenceShard()
            if reference_shard:IsValid() then
                reference_shard:SetNoDraw(true)
            end
        end)
    end
    
    // Receive crack visualization data
    net.Receive("GLASS_SHOW_CRACKS", function(len)
        local shard_entity = net.ReadEntity()
        local impact_pos = net.ReadVector()
        local impact_normal = net.ReadVector()
        local explode = net.ReadBool()
        
        if not shard_entity or not shard_entity:IsValid() then return end
        
        // Convert to local coordinates
        local local_pos = shard_entity:WorldToLocal(shard_entity:GetPos() + impact_pos)
        local local_normal = shard_entity:WorldToLocalAngles(impact_normal:Angle()):Forward()
        
        // Show cracks on client
        timer.Simple(0, function() // slight delay to ensure entity is ready
            if shard_entity and shard_entity:IsValid() and shard_entity.ShowCracks then
                shard_entity:ShowCracks(local_pos, local_normal)
            end
        end)
    end)
    
    // Receive glass no-collide data
    net.Receive("GLASS_NO_COLLIDE", function(len)
        local shard_entity = net.ReadEntity()
        local player_entity = net.ReadEntity()
        local should_be_passable = net.ReadBool()
        
        if not shard_entity or not shard_entity:IsValid() then return end
        
        if should_be_passable and player_entity and player_entity:IsValid() then
            shard_entity.passable_to_player = player_entity
            shard_entity:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
        else
            shard_entity.passable_to_player = nil
            shard_entity:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        end
    end)
end	

if SERVER then return end

// client initialize
hook.Add("InitPostEntity", "glass_init", function()
	timer.Simple(1, function()	// let SENT functions initialize, unsure why they arent in this hook.
		for k, v in ipairs(ents.FindByClass("procedural_shard")) do
			v:Initialize(true)
		end

		// tell server to send ALL shard data
		net.Start("SHARD_NETWORK")
		net.SendToServer()
	end)
end)
