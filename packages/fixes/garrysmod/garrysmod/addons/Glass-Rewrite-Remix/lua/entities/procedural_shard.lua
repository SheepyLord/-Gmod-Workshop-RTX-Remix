-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
local function NLC(player, text, ...)
    if NATIVELOADER_LOCALIZED_CHAT then
        NATIVELOADER_LOCALIZED_CHAT(player, text, {...})
    else
        player:ChatPrint(string.format(text, ...))
    end
end
local function NLP(key, text)
    if bundle_i18n then bundle_i18n.RegisterPhrase(key, text)
    elseif CLIENT then language.Add(key, text) end
end
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Category		= NL("Glass: Rewrite Remixed")
ENT.Author			= "CR (original by Mee)"
ENT.Purpose			= NL("Destructable Fun")
ENT.Instructions	= NL("Spawn and damage it")
ENT.Spawnable		= false

local generateUV, generateNormals, simplify_vertices, split_convex, are_verts_valid_for_phys = include("world_functions.lua")

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "PhysModel")
    self:NetworkVar("Vector", 0, "PhysScale")
    self:NetworkVar("Entity", 0, "ReferenceShard")
    self:NetworkVar("Entity", 1, "OriginalShard")
    self:NetworkVar("Float", 0, "FadeStart")    -- when a loose piece's lifetime ran out (0: it has not)
end

-- Read by glass_debris.lua, which gives loose pieces their collision group.
CreateConVar("rtx_glass_expensive_shards", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Broken glass pieces also collide with each other (1, more physics work) or only with the world and props (0); players always pass through them.", 0, 1)
CreateConVar("rtx_glass_debris_lifetime", 120, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Seconds broken glass pieces stay before they fade out (0 = until map cleanup or the 256-piece limit)", 0, 600)
local show_cracks = CreateConVar("rtx_glass_show_cracks", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Show visual cracks before glass breaks (1) or break immediately (0)", 0, 1)
local crack_delay = CreateConVar("rtx_glass_crack_delay", 0.05, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Delay in seconds between showing cracks and breaking", 0.05, 1.0)
local shard_count = CreateConVar("rtx_glass_shard_count", 12, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Controls number of glass shards (1=few, 7=many)", 1, 12)
local glass_rigidity = CreateConVar("rtx_glass_rigidity", 0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Glass damage threshold before breaking (0=fragile, 200=very strong)", 0, 200)
local mass_factor = CreateConVar("rtx_glass_mass_factor", 0.8, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "How much object mass affects impact force (0.5=less, 2.0=more)", 0.1, 3.0)
local velocity_transfer = CreateConVar("rtx_glass_velocity_transfer", 2.0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "How much impact velocity transfers to shards (0.5=less dramatic, 2.0=more)", 0.1, 3.0)
local player_mass = CreateConVar("rtx_glass_player_mass", 80, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Player mass in kg for glass breaking calculations (50=light, 100=heavy)", 30, 150)
local player_break_speed = CreateConVar("rtx_glass_player_break_speed", 80, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Minimum player speed to break glass (100=walking, 250=sprinting)", 50, 400)

-- Loose pieces (ADR 0061) broke off a pane: map window debris and the fragments of any shard. They are
-- interactive physics (glass_debris.lua), break again from damage or a hard impact until their
-- fragments are dust, and fade out at the end of their lifetime.
local TINY_RADIUS = 20          -- a fragment with a smaller bounding radius becomes GlassImpact dust
local LOOSE_BREAK_SPEED = 500   -- impact speed that breaks a loose piece (a pane breaks above 300);
                                -- at sv_gravity 600 a fall reaches it after about 210 units
local DUST_PER_SPLIT = 3        -- GlassImpact effects for the dust of one split
local DUST_PER_TICK = 24        -- an explosion over a pile breaks every piece in one tick
local FADE_TIME = 1             -- seconds an expired piece takes to shrink away

local function is_loose(ent)
    return ent.RTX_MAP_DEBRIS or ent:GetOriginalShard():IsValid()
end

local dust_tick, dust_count = -1, 0
local function glass_dust(pos)
    local tick = engine.TickCount()
    if tick != dust_tick then dust_tick, dust_count = tick, 0 end
    if dust_count >= DUST_PER_TICK then return end
    dust_count = dust_count + 1
    local data = EffectData()
    data:SetOrigin(pos)
    util.Effect("GlassImpact", data)
end

-- Half the diagonal of a fragment's bounds, which BoundingRadius reports once it is a shard, and its centre.
local function fragment_extent(tris)
    local low, high = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, vertex in ipairs(tris) do
        local p = vertex.pos or vertex
        low.x, low.y, low.z = math.min(low.x, p.x), math.min(low.y, p.y), math.min(low.z, p.z)
        high.x, high.y, high.z = math.max(high.x, p.x), math.max(high.y, p.y), math.max(high.z, p.z)
    end
    if low.x > high.x then return 0, Vector() end
    return (high - low):Length() * 0.5, (low + high) * 0.5
end

function ENT:BuildCollision(verts, pointer)
    local new_verts, offset = simplify_vertices(verts, self:GetPhysScale())
    
    -- The are_verts_valid_for_phys function now guarantees a valid set of verts,
    -- either the original ones or a new minimal tetrahedron.
    new_verts = are_verts_valid_for_phys(new_verts)

    self:EnableCustomCollisions()
	self:PhysicsInitConvex(new_verts)

    -- physics object isnt valid, remove cuz its probably weird
    if SERVER then
        local phys = self:GetPhysicsObject()
        if !phys:IsValid() then
            SafeRemoveEntity(self)
        else
            -- A fragment too small to keep becomes dust (Split leaves most of these out already). Its
            -- collision group comes from glass_debris.lua, like every loose piece's.
            if self:GetOriginalShard():IsValid() and self:BoundingRadius() < TINY_RADIUS then
                glass_dust(self:GetPos())
                SafeRemoveEntity(self)
                return
            end
            phys:SetMass(math.sqrt(phys:GetVolume()))
            phys:SetMaterial("glass")
            phys:SetPos(self:LocalToWorld(offset))
            self.TRIANGLES = phys:GetMesh()

            if pointer then pointer[1] = true end     -- cant return true because of weird SENT issues, just use table pointer to indicate success
        end
    else
        self:SetRenderBounds(self:OBBMins(), self:OBBMaxs())
        local phys = self:GetPhysicsObject()
        if phys:IsValid() then
            phys:SetMaterial("glass")
        end
    end
end

if CLIENT then
    function ENT:Think()
        local physobj = self:GetPhysicsObject()
        if !physobj:IsValid() then 
            self:SetNextClientThink(CurTime())
            return true
        end

        if (self:GetPos() == physobj:GetPos() and !physobj:IsMotionEnabled()) then
            self:SetNextClientThink(CurTime() + 0.1)
            return true
        end

        physobj:EnableMotion(false)
        physobj:SetPos(self:GetPos())
        physobj:SetAngles(self:GetAngles())
        self:SetNextClientThink(CurTime())
    end

    -- The shard's mesh is drawn here, not through DrawModel and GetRenderMesh: that route renders it
    -- through studiorender, which crashed on the material system's render thread (studiorender.dll
    -- +0x6603b, mat_queue_mode 2) whenever a shard was drawn in an RTX session (review R4: shooting a
    -- window on modern_house, or spawning any procedural glass, ended the game).
    function ENT:GetRenderMesh() end

    function ENT:Draw()
        local render_mesh = self.RENDER_MESH
        if !render_mesh or !render_mesh.Mesh or !render_mesh.Mesh:IsValid() then return end
        -- A loose piece whose lifetime ran out shrinks away over FADE_TIME before the server removes it.
        -- Only the transform changes: no mesh is built or freed while a queued frame may draw it.
        local scale = 1
        local fade = self:GetFadeStart()
        if fade > 0 then
            scale = math.Clamp(1 - (CurTime() - fade) / FADE_TIME, 0, 1)
            if scale < 0.05 then return end
        end
        local override = self:GetMaterial()
        if override != "" and override != self.drawn_material_name then
            self.drawn_material_name, self.drawn_material = override, Material(override)
        end
        local color = self:GetColor()
        render.SetMaterial(override != "" and self.drawn_material or render_mesh.Material)
        render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
        render.SetBlend(color.a / 255)
        local matrix = self:GetWorldTransformMatrix()
        if scale < 1 then matrix:Scale(Vector(scale, scale, scale)) end
        cam.PushModelMatrix(matrix)
        render_mesh.Mesh:Draw()
        cam.PopModelMatrix()
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)

        -- Draw crack overlay if present
        if self.crack_lines then
            self:DrawCracks()
        end
    end

    local function retire(mesh)
        if !mesh or !mesh:IsValid() then return end
        if GlassRewriteRetireMesh then GlassRewriteRetireMesh(mesh) else mesh:Destroy() end
    end

    function ENT:OnRemove()
        -- A frame queued before the removal may still draw these meshes (mat_queue_mode 2).
        if self.RENDER_MESH then
            retire(self.RENDER_MESH.Mesh)
            self.RENDER_MESH.Mesh = nil
        end
        retire(self.crack_mesh)
        self.crack_mesh = nil
    end
else
    function ENT:Split(pos, explode, skip_cracks)
        local self = self
        if explode then pos = pos * 0.5 end  -- if explosion, kind of "shrink" position closer to the center of the shard
        
        -- Store impact data for velocity calculations
        local impact_velocity = Vector(0, 0, 0)
        local impact_force_magnitude = 0
        
        -- Calculate impact velocity based on stored impact data
        if self.last_impact_normal and self.last_impact_speed then
            local base_speed = math.min(self.last_impact_speed, 800) -- Cap for reasonable physics
            local transfer_factor = velocity_transfer:GetFloat()
            impact_velocity = self.last_impact_normal * (base_speed * 0.3 * transfer_factor) -- Scale down for realistic effect
            impact_force_magnitude = base_speed
        end
        
        -- Add some random scatter for more realistic breaking
        local scatter_amount = explode and 200 or 100
        
        -- Show cracks first if enabled and not skipping
        if show_cracks:GetBool() and !skip_cracks and !self.showing_cracks then
            self.showing_cracks = true
            self.crack_impact_pos = pos
            self.crack_explode = explode
            
            -- Store impact data for delayed break
            self.stored_impact_velocity = impact_velocity
            self.stored_impact_force = impact_force_magnitude
            self.stored_scatter = scatter_amount
            
            -- Show cracks on all clients
            self:ShowCracks(pos, self.last_impact_normal)
            
            -- Send crack data to clients
            if SERVER then
                net.Start("GLASS_SHOW_CRACKS")
                net.WriteEntity(self)
                net.WriteVector(pos)
                net.WriteVector(self.last_impact_normal or Vector(0, 0, 1))
                net.WriteBool(explode or false)
                net.Broadcast()
            end
            
            -- Break after delay
            timer.Simple(crack_delay:GetFloat(), function()
                if !self or !self:IsValid() or !self.CAN_BREAK then return end
                self:Split(self.crack_impact_pos, self.crack_explode, true) -- skip cracks on delayed break
            end)
            
            return
        end
        
        -- Use stored impact data if this is a delayed break
        if self.stored_impact_velocity then
            impact_velocity = self.stored_impact_velocity
            impact_force_magnitude = self.stored_impact_force or 0
            scatter_amount = self.stored_scatter or 100
        end
        
        local convexes = {}
        local split_depth = shard_count:GetInt() -- Use console variable as base
        local loose = is_loose(self)
        
        if loose then
            -- A piece that already broke off cracks into a few fragments, so that it can be broken
            -- again and again until its fragments are dust.
            split_depth = math.max(2, math.ceil(split_depth / 4))
        else
            -- The first break of an original piece of glass creates more shards.
            split_depth = split_depth + math.random(2, 4) -- Add 2 to 4 extra "levels" of cracks.
        end

        -- Create realistic glass fracture patterns
        local impact_pos = pos
        local impact_normal = self.last_impact_normal or (self:GetPos() - self:LocalToWorld(pos)):GetNormalized()
        local shard_size = self:BoundingRadius()
        local planes = {}
        local num_radial_cracks = math.random(math.max(2, split_depth - 1), split_depth + 2)
        local num_concentric_cracks = math.random(split_depth - 2, split_depth)

        -- 1. Generate Radial Cracks
        local primary_radial_dir = impact_normal:Cross(VectorRand()):GetNormalized()
        for i = 1, num_radial_cracks do
            local angle = Angle(0, (360 / num_radial_cracks) * i + math.Rand(-10, 10), 0)
            local radial_dir = primary_radial_dir
            radial_dir:Rotate(angle)
            
            -- Add a bit of vertical randomness
            radial_dir.z = radial_dir.z + math.Rand(-0.3, 0.3)
            
            table.insert(planes, {pos = impact_pos, dir = radial_dir:GetNormalized()})
        end

        -- 2. Generate Concentric Cracks
        if num_concentric_cracks > 0 then
            local max_dist = shard_size * math.Rand(0.7, 1.0)
            for i = 1, num_concentric_cracks do
                local dist_from_center = (max_dist / num_concentric_cracks) * i
                local crack_pos = impact_pos + impact_normal * dist_from_center * math.Rand(0.8, 1.2)
                
                -- The plane normal for a concentric crack is the impact normal
                table.insert(planes, {pos = crack_pos, dir = impact_normal})
            end
        end

        -- New iterative splitting logic
        local shards_to_process = {{verts = self.TRIANGLES}}
        
        -- Process planes one by one, splitting the largest available shard each time
        for i = 1, #planes do
            if #shards_to_process == 0 then break end

            -- Find the largest shard to split next
            local largest_shard_index = -1
            local max_verts = -1
            for j, shard in ipairs(shards_to_process) do
                if #shard.verts > max_verts then
                    max_verts = #shard.verts
                    largest_shard_index = j
                end
            end
            
            if largest_shard_index == -1 then break end
            
            -- Remove the largest shard from the list to be replaced by its children
            local shard_to_split = table.remove(shards_to_process, largest_shard_index)
            local plane = planes[i]
            
            local split_1 = split_convex(shard_to_split.verts, plane.pos, plane.dir)
            local split_2 = split_convex(shard_to_split.verts, plane.pos, -plane.dir)
            
            -- If a split results in a valid shard, add it back to the list
            if #split_1 > 3 then table.insert(shards_to_process, {verts = split_1}) end
            if #split_2 > 3 then table.insert(shards_to_process, {verts = split_2}) end
        end

        -- All remaining shards in shards_to_process are our final convexes
        for _, shard in ipairs(shards_to_process) do
             table.insert(convexes, {shard.verts})
        end
        
        local pos = self:GetPos()
        local ang = self:GetAngles()
        local model = self:GetPhysModel()
        local material = self:GetMaterial()
        local color = self:GetColor()
        local rendermode = self:GetRenderMode()
        local vel = self:GetVelocity()
        local phys_scale = self:GetPhysScale()
        local original_shard = self:GetOriginalShard():IsValid() and self:GetOriginalShard() or self
        local lastblock
        local valid_entity = {false}      -- table cuz i want pointers
        local dust = 0
        self.GLASS_BREAKING = true    -- its fragments take its place in the budget (glass_debris.lua)
        self:EmitSound("Glass.Break")
        for k, physmesh in ipairs(convexes) do 
            -- Every fragment has an original shard, so one below TINY_RADIUS would only be removed again in
            -- BuildCollision: it becomes dust without an entity. An explosion over a pile breaks every piece
            -- in one tick, and creating and dropping all their dust as entities could run out of edicts.
            local radius, center = fragment_extent(physmesh[1])
            if radius < TINY_RADIUS then
                dust = dust + 1
                if dust <= DUST_PER_SPLIT then glass_dust(self:LocalToWorld(center)) end
                continue
            end

            local block = ents.Create("procedural_shard")
            block:SetPos(pos)
            block:SetAngles(ang)
            block:SetPhysModel(model)
            block:SetPhysScale(Vector(1, 1, 1))
            block:SetOriginalShard(original_shard)
            block:Spawn()
            block:SetReferenceShard(self)
            block:SetMaterial(material)
            block:SetColor(color)
            block:SetRenderMode(rendermode)
            local built = {false}
            block:BuildCollision(physmesh[1], built)   -- first thing in table is the triangles
            if built[1] then valid_entity[1] = true end
            block.IS_FUNNY_GLASS = self.IS_FUNNY_GLASS
            
            -- Inherit a portion of accumulated damage (shards are weaker)
            if self.accumulated_damage and self.accumulated_damage > 0 then
                block.accumulated_damage = math.max(0, self.accumulated_damage * 0.3) -- Shards inherit 30% of damage
            else
                block.accumulated_damage = 0
            end
            
            local phys = block:GetPhysicsObject()
            if built[1] and phys:IsValid() then
                -- A loose piece: interactive physics, the shared budget and the lifetime (glass_debris.lua).
                if GlassRewriteDebris then GlassRewriteDebris.Add(block) end

                -- Calculate realistic shard velocity based on impact
                local shard_velocity = Vector(vel.x, vel.y, vel.z) -- Start with original glass velocity
                local transfer_factor = velocity_transfer:GetFloat()

                if impact_velocity:Length() > 0 then
                    -- Get the center of this shard relative to impact point
                    local shard_center = block:LocalToWorld(block:OBBCenter())
                    local impact_world_pos = self:LocalToWorld(impact_pos)
                    local impact_to_shard = (shard_center - impact_world_pos)
                    
                    -- Calculate distance factor (closer shards get more velocity)
                    local distance = impact_to_shard:Length()
                    if distance < 1 then distance = 1 end -- Prevent division by zero
                    local distance_factor = math.Clamp(1 - (distance / self:BoundingRadius()), 0.1, 1)

                    -- NEW Velocity Model:
                    -- 1. Base force pushing directly away from the impact point.
                    local radial_force = impact_to_shard:GetNormalized() * (impact_force_magnitude * 0.3 * distance_factor * transfer_factor)

                    -- 2. Inherit some of the original impact's direction and force.
                    local inherited_force = impact_velocity * (0.8 * distance_factor * transfer_factor)
                    
                    -- 3. Add a small amount of chaotic scatter.
                    local scatter = VectorRand() * (scatter_amount * 0.5 * distance_factor * transfer_factor)

                    shard_velocity = shard_velocity + radial_force + inherited_force + scatter
                end
                
                phys:SetVelocity(shard_velocity)

                -- NEW: Add realistic angular velocity (spin/torque)
                -- The amount of spin is based on the impact force and shard's distance from the impact.
                local rotational_force = math.min(impact_force_magnitude * 1.5, 1200) * transfer_factor
                local random_spin = VectorRand() * rotational_force
                phys:AddAngleVelocity(random_spin)
            end
            
            -- prop protection support
            if CPPI then
                local owner = self:CPPIGetOwner()
                if owner and owner:IsValid() then
                    block:CPPISetOwner(owner)
                end
            end

            -- weld it to other shards (a pane's first break; the fragments of a loose piece stay apart)
            if lastblock and !loose then
                constraint.Weld(block, lastblock, 0, 0, 3000, true)
            end
            if built[1] then lastblock = block end
        end

        -- all shards have been removed because they are too small, remove the original
        if !valid_entity[1] then SafeRemoveEntity(self) return end

        -- From here on a hidden placeholder, counted out of its original below (OnRemove must not again).
        self.GLASS_SPLIT = true
        constraint.RemoveAll(self)
        self:GetPhysicsObject():EnableMotion(false)
        self:SetNotSolid(true)
        self:ForcePlayerDrop()
        self.CAN_BREAK = false
        
        -- Clean up crack state and impact data
        self.showing_cracks = false
        self.crack_lines = nil
        self.stored_impact_velocity = nil
        self.stored_impact_force = nil
        self.stored_scatter = nil
        if self.crack_mesh then
            self.crack_mesh:Destroy()
            self.crack_mesh = nil
        end

        -- this shard is now invalid, decriment the original shards count
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then 
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT - 1
        end

        -- in case clientside receives sharded entity before this entity
        -- give clients 5 seconds to try and find shard
        timer.Simple(5, function()
            if !self:IsValid() then return end
            -- A fragment that broke again is not needed after that: its fragments count towards the
            -- original. The original stays hidden until its last fragment is gone (OnRemove).
            if self:GetOriginalShard():IsValid() then SafeRemoveEntity(self) return end
            self:SetPos(Vector())
            self:SetAngles(Angle())
            self:SetNoDraw(true)
        end)
        
    end

    function ENT:OnTakeDamage(damage)
        -- Defining OnTakeDamage replaces base_anim's, so bullets, blasts and melee move nothing unless the
        -- entity applies their force itself (as GMod's own entities do). A frozen pane does not move.
        self:TakePhysicsDamage(damage)
        if !self.CAN_BREAK or self.showing_cracks then return end
        local damagepos = damage:GetDamagePosition()
        if damagepos != Vector() then -- some physents are broken and have no damage position, so just set the damage to the center of the object
            damagepos = self:WorldToLocal(damagepos)
        else
            damagepos = Vector()
        end
        
        -- Store damage data for realistic cracking patterns
        local attacker = damage:GetAttacker()
        if attacker and attacker:IsValid() then
            -- Calculate impact direction from attacker to glass
            local impact_dir = (self:GetPos() - attacker:GetPos()):GetNormalized()
            self.last_impact_normal = impact_dir
        else
            -- Fallback to random direction if no attacker info
            self.last_impact_normal = VectorRand():GetNormalized()
        end
        self.last_impact_speed = damage:GetDamage() * 10 -- simulate speed from damage
        
        -- Rigidity system: fast impacts break immediately, slow impacts accumulate
        local damage_amount = damage:GetDamage()
        local damage_type = damage:GetDamageType()
        local rigidity_threshold = glass_rigidity:GetFloat()
        local should_break = false
        
        -- Fast impacts that should break immediately regardless of rigidity
        local is_fast_impact = (
            damage_type == DMG_BLAST           -- explosions
        )
        
        if is_fast_impact or rigidity_threshold <= 0 then
            -- Break immediately for fast impacts or when rigidity disabled
            should_break = true
        else
            -- Accumulate damage for slow impacts
            self.accumulated_damage = (self.accumulated_damage or 0) + damage_amount
            
            if self.accumulated_damage >= rigidity_threshold then
                should_break = true
            else
                -- Show minor crack effect without breaking
                if show_cracks:GetBool() and math.random() < 0.3 then -- 30% chance for minor cracks
                    self:ShowCracks(damagepos, self.last_impact_normal)
                end
                
                -- Play glass stress sound
                self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 40, math.random(120, 150))
                
                -- Visual feedback for damage accumulation
                if attacker and attacker:IsPlayer() then
                    NLC(attacker, NN("Glass damage: %d / %d"), math.Round(self.accumulated_damage), math.Round(rigidity_threshold))
                end
                
                return -- Don't break yet
            end
        end
        
        if should_break then
            -- Reset damage counter when breaking
            self.accumulated_damage = 0
            
            self:Split(damagepos, damage:GetDamageType() == DMG_BLAST)
            if !show_cracks:GetBool() then
                self.CAN_BREAK = false
            end
        end
    end

    function ENT:PhysicsCollide(data)
    	if self:IsPlayerHolding() then return end	--unbreakable if held
        -- A loose piece lies where it fell: falling out of a window does not break it again, a hard hit does.
        local loose = is_loose(self)
        local speed_limit = self.IS_FUNNY_GLASS and -1 or (loose and LOOSE_BREAK_SPEED or 300)
    	if data.Speed > speed_limit and self.CAN_BREAK and !self.showing_cracks then
            local ho = data.HitObject
            -- The pieces of a pile collide: two loose pieces never break each other. (HitObject is the other
            -- physics object, so the check on it below never matches; the entity is HitEntity.)
            local hit = data.HitEntity
            if loose and IsValid(hit) and hit:GetClass() == "procedural_shard" and is_loose(hit) then return end
            if ho and ho:IsValid() and ho.GetClass and ho:GetClass() == "procedural_shard" and ho.CAN_BREAK then return end

            -- just some values that I thought looked nice
            local limit = 0.25
            if ho.GetClass and ho:GetClass() == "procedural_shard" then limit = -0.25 end   -- less lag
            if self.IS_FUNNY_GLASS then limit = 2 end  -- impossible to not break

            -- if the glass is directly struck straightways, dont break since this can cause break loops
            local dot = data.OurNewVelocity:GetNormalized():Dot(data.OurOldVelocity:GetNormalized())
            if dot > limit then return end
           
            local pos = data.HitPos
            
            -- Store impact data for realistic cracking
            self.last_impact_normal = data.HitNormal
            self.last_impact_speed = data.Speed
            
            -- Enhanced rigidity system considering mass and velocity
            local impact_speed = data.Speed
            local impact_mass = 1 -- Default mass if we can't get it
            
            -- Try to get the mass of the impacting object
            if ho and ho:IsValid() and ho.GetPhysicsObject and ho:GetPhysicsObject():IsValid() then
                impact_mass = ho:GetPhysicsObject():GetMass()
            end
            
            -- Apply mass factor scaling
            local adjusted_mass = impact_mass * mass_factor:GetFloat()
            
            -- Calculate impact force using momentum (mass * velocity)
            -- Add some kinetic energy consideration (0.5 * mass * velocity^2)
            local momentum = adjusted_mass * impact_speed
            local kinetic_energy = 0.5 * adjusted_mass * (impact_speed * impact_speed) / 1000 -- Scale down for reasonable numbers
            local impact_force = momentum + (kinetic_energy * 0.1) -- Combine momentum and kinetic energy
            
            -- Convert impact force to damage equivalent 
            local collision_damage = impact_force / 15 -- Adjust this divisor to balance
            
            local rigidity_threshold = glass_rigidity:GetFloat()
            local should_break = false
            
            -- Fast impacts that should break immediately regardless of rigidity
            local is_fast_impact = (
                damage_type == DMG_BLAST           -- explosions
            )
            
            if is_fast_impact or rigidity_threshold <= 0 then
                -- Break immediately for fast impacts or when rigidity disabled
                should_break = true
            else
                -- Accumulate damage for lesser impacts
                self.accumulated_damage = (self.accumulated_damage or 0) + collision_damage
                
                if self.accumulated_damage >= rigidity_threshold then
                    should_break = true
                else
                    -- Show minor crack effect without breaking
                    if show_cracks:GetBool() and math.random() < math.min(0.5, collision_damage / 30) then 
                        -- Higher chance of cracks for stronger impacts
                        local local_pos = self:WorldToLocal(pos)
                        self:ShowCracks(local_pos, self.last_impact_normal)
                    end
                    
                    -- Play glass stress sound (pitch varies with impact force)
                    local pitch = math.Clamp(120 + (impact_force / 100), 90, 180)
                    self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 30, pitch)
                    
                    return -- Don't break yet
                end
            end
            
            if should_break then
                -- Reset damage counter when breaking
                self.accumulated_damage = 0
                
                timer.Simple(0, function() -- NEVER change collision rules in physics feedback
                    if !self or !self:IsValid() then return end
                    self:Split(self:WorldToLocal(pos))
                    if !show_cracks:GetBool() then
                        self.CAN_BREAK = false
                    end
                end)
            end
    	end
	end	

    function ENT:Touch(entity)
        if !self.CAN_BREAK or self.showing_cracks then return end
        if !entity:IsPlayer() then return end
        
        -- Prevent spam by adding a small cooldown per player
        local current_time = CurTime()
        local player_id = entity:SteamID()
        self.player_touch_cooldowns = self.player_touch_cooldowns or {}
        
        if self.player_touch_cooldowns[player_id] and (current_time - self.player_touch_cooldowns[player_id]) < 0.5 then
            return -- Still in cooldown
        end
        
        -- Get player movement data
        local player_velocity = entity:GetVelocity()
        local player_speed = player_velocity:Length()
        
        -- Minimum speed threshold for glass breaking (walking speed ~100, running speed ~200+)
        local min_break_speed = player_break_speed:GetInt() -- Players need to be moving at least this fast
        if player_speed < min_break_speed then return end
        
        -- Set cooldown for this player (they're moving fast enough to potentially break glass)
        self.player_touch_cooldowns[player_id] = current_time
        
        -- Estimate player mass (average adult ~70kg, can be adjusted)
        local player_mass_kg = player_mass:GetInt()
        
        -- Calculate player impact force using the same system as physics objects
        local adjusted_mass = player_mass_kg * mass_factor:GetFloat()
        local momentum = adjusted_mass * player_speed
        local kinetic_energy = 0.5 * adjusted_mass * (player_speed * player_speed) / 1000
        local impact_force = momentum + (kinetic_energy * 0.1)
        local collision_damage = impact_force / 15
        
        local rigidity_threshold = glass_rigidity:GetFloat()
        local should_break = false
        
        -- Fast running players should break glass immediately
        local is_fast_player = player_speed > 250 -- Sprinting speed
        
        if is_fast_player or rigidity_threshold <= 0 then
            should_break = true
        else
            -- Accumulate damage for slower movement
            self.accumulated_damage = (self.accumulated_damage or 0) + collision_damage
            
            if self.accumulated_damage >= rigidity_threshold then
                should_break = true
            else
                -- Show minor crack effect without breaking
                if show_cracks:GetBool() and math.random() < math.min(0.4, collision_damage / 25) then
                    local contact_pos = entity:GetPos() - self:GetPos()
                    local local_pos = self:WorldToLocal(entity:GetPos())
                    self:ShowCracks(local_pos, player_velocity:GetNormalized())
                end
                
                -- Play glass stress sound
                local pitch = math.Clamp(100 + (player_speed / 5), 80, 160)
                self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 40, pitch)
                
                return -- Don't break yet
            end
        end
        
        if should_break then
            -- Store player impact data for realistic shard physics
            self.last_impact_normal = player_velocity:GetNormalized()
            self.last_impact_speed = player_speed
            self.accumulated_damage = 0
            
            -- Calculate impact position (where player touches glass)
            local contact_pos = entity:GetPos() - self:GetPos()
            local local_impact_pos = self:WorldToLocal(entity:GetPos())
            
            -- Break the glass with player impact data
            self:Split(local_impact_pos, false) -- Not an explosion
            if !show_cracks:GetBool() then
                self.CAN_BREAK = false
            end
        end
    end

    -- The end of a loose piece's lifetime (glass_debris.lua): clients shrink it away over FADE_TIME
    -- (ENT:Draw), then it goes. It keeps moving meanwhile, and it no longer breaks.
    function ENT:FadeOut()
        if self.GLASS_FADING then return end
        self.GLASS_FADING = true
        self.CAN_BREAK = false
        self:SetFadeStart(CurTime())
        self:ForcePlayerDrop()
        timer.Simple(FADE_TIME, function()
            if IsValid(self) then self:Remove() end
        end)
    end

    function ENT:OnRemove()
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then 
            if self.GLASS_SPLIT then return end -- counted out when it broke
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT - 1
            if orig_shard.SHARD_COUNT < 1 then
                SafeRemoveEntity(orig_shard)
            end
        elseif self.GLASS_SPLIT then    -- must be original shard, remove parent shards
            -- (map debris and panes that never broke have none, and need no search)
            for k, v in ipairs(ents.FindByClass("procedural_shard")) do
                if v.GetOriginalShard and v:GetOriginalShard() == self then
                    SafeRemoveEntity(v)
                end
            end
        end
    end
end

function ENT:OnDuplicated()
    self:BuildCollision(util.GetModelMeshes(self:GetPhysModel())[1].triangles)
end


local default_mat = Material("models/props_combine/health_charger_glass")
function ENT:Initialize(first)
    --self:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:PhysWake()
    self:DrawShadow(false)

    if SERVER then 
        self.CAN_BREAK = false
        self.accumulated_damage = 0 -- Track damage for rigidity system
        -- if valid to completely remove
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT + 1
        else
            self.SHARD_COUNT = 0    -- it is the original shard
        end

        -- remove fast & laggy interactions (map debris breaks again too, ADR 0061)
        timer.Simple(0.25, function()
            if !IsValid(self) or self.GLASS_FADING or self.GLASS_BREAKING then return end
            self.CAN_BREAK = true
        end)

        return 
    end

    self.RENDER_MESH = {Material = default_mat}   -- the mesh arrives with the shard's data (networking.lua)
    
    if first then return end

    -- tell server to start sending shard data
    net.Start("SHARD_NETWORK")
    net.WriteEntity(self)
    net.SendToServer()
end

-- make sure clients can always see entity, reguardless if not in view
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

if CLIENT then 
    NLP("procedural_shard", NN("Glass Shard"))
    return 
end

-- glass func_breakable_surf replacement
local function replaceGlass()
    for _, glass in ipairs(ents.FindByClass("func_breakable_surf")) do
        -- func breakable surf is kinda cursed, its origin and angle are always 0,0,0
        -- so we need to find out what they are

        -- angle can be found by going through 3 of the 4 points defined on a surf entity and finding the angle by constructing a triangle
        local verts = glass:GetBrushSurfaces()[1]:GetVertices()
        local glass_angle = (verts[1] - verts[2]):Cross(verts[1] - verts[3]):Angle()

        -- position can be found by getting the middle of the bounding box in the object
        local offset = (glass:OBBMaxs() + glass:OBBMins()) * 0.5

        -- weird rotate issue fix
        local rotate_angle = glass_angle
        if glass_angle[1] >= 45 and glass_angle[2] >= 180 then
            rotate_angle = -rotate_angle
        end

        -- our bounding box needs to be rotated to match the angle of the glass, the rotation is currently in local space, we need to convert to world
        verts[1] = verts[1] - offset
        verts[3] = verts[3] - offset
        verts[1]:Rotate(-rotate_angle)
        verts[3]:Rotate(-rotate_angle)

        -- now we have the actual size of the glass, take the 2 points and subtract to find the size, then divide by 2
        local size = (verts[1] - verts[3]) * 0.5

        -- create the shard
        local block = ents.Create("procedural_shard")
        block:SetPhysModel("models/hunter/blocks/cube025x025x025.mdl")
        block:SetPhysScale(Vector(1, size[2], size[3]) / 5.90625)  -- 5.90625 is the size of the block model
        block:SetPos(offset)
        block:SetAngles(glass_angle)
        block:SetMaterial(glass:GetMaterials()[1])
        block:Spawn()
    
        block:BuildCollision(util.GetModelMeshes("models/hunter/blocks/cube025x025x025.mdl")[1].triangles)
        if block:GetPhysicsObject():IsValid() then block:GetPhysicsObject():EnableMotion(false) end

        -- remove original func_ entity
        SafeRemoveEntity(glass)
    end
end

hook.Add("InitPostEntity", "glass_init", replaceGlass)
hook.Add("PostCleanupMap", "glass_init", replaceGlass)

-- Console commands for crack system
if SERVER then    
    concommand.Add("rtx_glass_reset_damage", function(ply, cmd, args)
        if !ply:IsSuperAdmin() then return end
        
        local tr = ply:GetEyeTrace()
        if tr.Entity and tr.Entity:GetClass() == "procedural_shard" then
            local shard = tr.Entity
            local old_damage = shard.accumulated_damage or 0
            shard.accumulated_damage = 0
            NLC(ply, NN("Reset glass damage from %d to 0"), math.Round(old_damage))
        else
            NLC(ply, NN("Look at a glass shard to reset its damage"))
        end
    end, nil, "Reset accumulated damage on looked-at glass (Admin only)")
    
    concommand.Add("rtx_glass_panel", function(ply, cmd, args)
        NLC(ply, NN("Opening Glass Settings Panel..."))
        NLC(ply, NN("Run glass_open_panel in the console or open RTX Remix > Water and glass > Settings in the spawn menu."))
    end, nil, "Instructions to open the glass settings panel")
end

-- Crack visualization system
function ENT:GenerateCrackLines(impact_pos, impact_normal)
    if !show_cracks:GetBool() then return {} end
    
    local crack_lines = {}
    local shard_size = self:BoundingRadius()
    local max_crack_length = shard_size * 0.8
    
    -- Convert impact position to surface position if we have a normal
    local surface_pos = impact_pos
    if impact_normal then
        -- Project impact point onto the glass surface using server-compatible bounds
        local bounds_min, bounds_max = self:OBBMins(), self:OBBMaxs()
        local surface_offset = (bounds_max.z - bounds_min.z) * 0.5
        surface_pos = impact_pos + impact_normal * surface_offset * 0.1
    end
    
    -- Generate primary radial cracks
    local primary_cracks = math.random(4, 7)
    for i = 1, primary_cracks do
        local angle = (i / primary_cracks) * math.pi * 2 + math.random(-0.3, 0.3)
        local crack_dir = Vector(math.cos(angle), math.sin(angle), math.random(-0.1, 0.1)):GetNormalized()
        
        -- Vary crack length based on impact strength
        local crack_length = max_crack_length * math.random(0.4, 1.0)
        if self.last_impact_speed then
            crack_length = crack_length * math.min(2.0, self.last_impact_speed / 200)
        end
        
        local crack_end = surface_pos + crack_dir * crack_length
        table.insert(crack_lines, {surface_pos, crack_end, 2.0}) -- start, end, width
    end
    
    -- Generate secondary branching cracks
    local secondary_cracks = math.random(2, 4)
    for i = 1, secondary_cracks do
        local base_angle = math.random() * math.pi * 2
        local branch_angle = base_angle + math.random(-0.8, 0.8)
        local crack_dir = Vector(math.cos(branch_angle), math.sin(branch_angle), math.random(-0.2, 0.2)):GetNormalized()
        
        -- Secondary cracks start partway along primary crack paths
        local start_offset = crack_dir:Cross(Vector(0, 0, 1)):GetNormalized() * math.random(10, 30)
        local crack_start = surface_pos + start_offset
        local crack_end = crack_start + crack_dir * (max_crack_length * math.random(0.2, 0.6))
        
        table.insert(crack_lines, {crack_start, crack_end, 1.5}) -- thinner secondary cracks
    end
    
    -- Generate small tertiary cracks for detail
    local detail_cracks = math.random(3, 6)
    for i = 1, detail_cracks do
        local random_angle = math.random() * math.pi * 2
        local crack_dir = Vector(math.cos(random_angle), math.sin(random_angle), math.random(-0.3, 0.3)):GetNormalized()
        
        local start_offset = VectorRand() * (shard_size * 0.3)
        local crack_start = surface_pos + start_offset
        local crack_end = crack_start + crack_dir * (max_crack_length * math.random(0.1, 0.3))
        
        table.insert(crack_lines, {crack_start, crack_end, 1.0}) -- thin detail cracks
    end
    
    return crack_lines
end

function ENT:ShowCracks(impact_pos, impact_normal)
    if !show_cracks:GetBool() then return end
    
    -- Generate crack pattern
    local crack_lines = self:GenerateCrackLines(impact_pos, impact_normal)
    if #crack_lines == 0 then return end
    
    -- Store cracks for rendering
    self.crack_lines = crack_lines
    self.crack_alpha = 255
    self.crack_start_time = CurTime()
    
    -- Play crack sound effect
    self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 60, math.random(90, 110))
    
    if CLIENT then
        -- Create crack mesh overlay
        self:UpdateCrackMesh()
    end
end

if CLIENT then
    function ENT:UpdateCrackMesh()
        if !self.crack_lines or #self.crack_lines == 0 then return end
        
        -- Create crack geometry
        local crack_verts = {}
        local vert_count = 0
        
        for _, crack_data in ipairs(self.crack_lines) do
            local start_pos, end_pos, width = crack_data[1], crack_data[2], crack_data[3]
            
            -- Create a thin quad for each crack line
            local crack_vec = (end_pos - start_pos):GetNormalized()
            local crack_perp = crack_vec:Cross(Vector(0, 0, 1)):GetNormalized() * (width * 0.5)
            
            -- Four corners of the crack quad
            local v1 = start_pos + crack_perp
            local v2 = start_pos - crack_perp  
            local v3 = end_pos - crack_perp
            local v4 = end_pos + crack_perp
            
            -- First triangle
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v1, normal = Vector(0, 0, 1), u = 0, v = 0}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v2, normal = Vector(0, 0, 1), u = 1, v = 0}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v3, normal = Vector(0, 0, 1), u = 1, v = 1}
            
            -- Second triangle
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v1, normal = Vector(0, 0, 1), u = 0, v = 0}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v3, normal = Vector(0, 0, 1), u = 1, v = 1}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v4, normal = Vector(0, 0, 1), u = 0, v = 1}
        end
        
        -- A new crack mesh each time: rebuilding one a queued frame may still draw is not safe.
        if #crack_verts > 0 then
            local fresh = Mesh()
            fresh:BuildFromTriangles(crack_verts)
            local old = self.crack_mesh
            self.crack_mesh = fresh
            if old and old:IsValid() then
                if GlassRewriteRetireMesh then GlassRewriteRetireMesh(old) else old:Destroy() end
            end
        end
    end
    
    function ENT:DrawCracks()
        if !self.crack_lines or !self.crack_mesh then return end
        
        -- Fade out cracks over time
        local fade_time = crack_delay:GetFloat() * 0.8
        local time_since_crack = CurTime() - (self.crack_start_time or 0)
        
        if time_since_crack > fade_time then
            local fade_progress = math.min(1, (time_since_crack - fade_time) / (crack_delay:GetFloat() * 0.2))
            self.crack_alpha = 255 * (1 - fade_progress)
            
            if self.crack_alpha <= 10 then
                self.crack_lines = nil
                if self.crack_mesh then
                    -- Retired, not destroyed: a queued frame may still draw it (mat_queue_mode 2).
                    if GlassRewriteRetireMesh then GlassRewriteRetireMesh(self.crack_mesh) else self.crack_mesh:Destroy() end
                    self.crack_mesh = nil
                end
                return
            end
        end
        
        -- Set up rendering for cracks
        render.SetMaterial(Material("effects/laser1"))
        render.SetColorMaterial()
        
        -- Draw crack mesh with transparency
        render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA)
        render.SetColorModulation(0.1, 0.1, 0.1) -- Dark crack color
        
        local matrix = Matrix()
        matrix:SetTranslation(self:GetPos())
        matrix:SetAngles(self:GetAngles())
        
        cam.PushModelMatrix(matrix)
        self.crack_mesh:Draw()
        cam.PopModelMatrix()
        
        render.OverrideBlend(false)
    end
end
