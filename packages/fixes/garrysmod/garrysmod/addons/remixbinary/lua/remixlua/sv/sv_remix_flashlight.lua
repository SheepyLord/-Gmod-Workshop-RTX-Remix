if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not SERVER then return end

-- Server-side multiplayer flashlight state management

util.AddNetworkString("rtx_flashlight_state")
util.AddNetworkString("rtx_flashlight_toggle")
util.AddNetworkString("rtx_flashlight_update_color")

-- Track flashlight states and colors per player
local playerFlashlightStates = {} -- [player] = { active = bool, color = Color() }

-- R19 (the pre-release review's F-04): a client's messages cost at most one broadcast per cooldown.
-- A switch waits out the shared debounce (sh_flashlight_override.lua's 0.3 s); colours are
-- coalesced, the newest one sent at most every COLOR_INTERVAL.
local TOGGLE_COOLDOWN = 0.3
local COLOR_INTERVAL = 0.1
local lastToggle, lastColorSent, pendingColor = {}, {}, {}

local function ToggleTooSoon(ply)
    local now = SysTime()
    if lastToggle[ply] and now - lastToggle[ply] < TOGGLE_COOLDOWN then return true end
    lastToggle[ply] = now
    return false
end

-- R19 (the review's miss): whether a player may switch a flashlight on, as the gamemode decides
-- without this override (base: ply:CanUseFlashlight(), spectators only off). Dead players get none.
-- Switching off is always allowed.
local function MayUseFlashlight(ply, on)
    if not on then return true end
    if not IsValid(ply) or not ply:Alive() then return false end
    if ply.CanUseFlashlight and not ply:CanUseFlashlight() then return false end
    local gm = gmod.GetGamemode()
    if gm and gm.PlayerSwitchFlashlight then
        local ok, allowed = pcall(gm.PlayerSwitchFlashlight, gm, ply, on)
        if ok and allowed == false then return false end
    end
    return true
end

-- Toggle flashlight for a player
local function TogglePlayerFlashlight(ply, r, g, b)
    if not IsValid(ply) then return end
    
    -- Initialize if needed
    if not playerFlashlightStates[ply] then
        playerFlashlightStates[ply] = { active = false, color = Color(255, 240, 200) }
    end
    
    -- Toggle state, on only where the gamemode allows a flashlight
    local turnOn = not playerFlashlightStates[ply].active
    if turnOn and not MayUseFlashlight(ply, true) then return end
    playerFlashlightStates[ply].active = turnOn
    
    -- Update color if provided
    if r and g and b then
        playerFlashlightStates[ply].color = Color(r, g, b)
    end
    
    -- Broadcast to all clients
    net.Start("rtx_flashlight_state")
    net.WriteEntity(ply)
    net.WriteBool(playerFlashlightStates[ply].active)
    net.WriteUInt(playerFlashlightStates[ply].color.r, 8)
    net.WriteUInt(playerFlashlightStates[ply].color.g, 8)
    net.WriteUInt(playerFlashlightStates[ply].color.b, 8)
    net.Broadcast()
end

-- Receive toggle request from client with color data
net.Receive("rtx_flashlight_toggle", function(len, ply)
    if not IsValid(ply) or ToggleTooSoon(ply) then return end
    local r = net.ReadUInt(8)
    local g = net.ReadUInt(8)
    local b = net.ReadUInt(8)
    TogglePlayerFlashlight(ply, r, g, b)
end)

-- Broadcast a player's current colour while the flashlight is on
local function BroadcastColor(ply)
    local state = playerFlashlightStates[ply]
    if not IsValid(ply) or not state or not state.active then return end
    lastColorSent[ply] = SysTime()
    net.Start("rtx_flashlight_update_color")
    net.WriteEntity(ply)
    net.WriteUInt(state.color.r, 8)
    net.WriteUInt(state.color.g, 8)
    net.WriteUInt(state.color.b, 8)
    net.Broadcast()
end

-- Receive color update from client (real-time adjustment)
net.Receive("rtx_flashlight_update_color", function(len, ply)
    if not IsValid(ply) then return end
    
    local r = net.ReadUInt(8)
    local g = net.ReadUInt(8)
    local b = net.ReadUInt(8)
    
    -- Initialize if needed
    if not playerFlashlightStates[ply] then
        playerFlashlightStates[ply] = { active = false, color = Color(255, 240, 200) }
    end
    
    -- Update color
    playerFlashlightStates[ply].color = Color(r, g, b)
    
    -- If flashlight is active, broadcast the update to all clients: at once, or the newest colour
    -- when the interval has passed
    if not playerFlashlightStates[ply].active then return end
    local wait = COLOR_INTERVAL - (SysTime() - (lastColorSent[ply] or 0))
    if wait <= 0 then
        BroadcastColor(ply)
    elseif not pendingColor[ply] then
        pendingColor[ply] = true
        timer.Simple(wait, function()
            pendingColor[ply] = nil
            BroadcastColor(ply)
        end)
    end
end)

-- Clean up when player disconnects
hook.Add("PlayerDisconnected", "RTXFlashlight_Cleanup", function(ply)
    playerFlashlightStates[ply] = nil
    lastToggle[ply], lastColorSent[ply], pendingColor[ply] = nil, nil, nil
    
    -- Tell clients to remove this player's flashlight
    net.Start("rtx_flashlight_state")
    net.WriteEntity(ply)
    net.WriteBool(false)
    net.WriteUInt(255, 8)
    net.WriteUInt(240, 8)
    net.WriteUInt(200, 8)
    net.Broadcast()
end)

-- Send all current flashlight states to a newly connected player
hook.Add("PlayerInitialSpawn", "RTXFlashlight_SyncStates", function(ply)
    timer.Simple(1, function()
        if not IsValid(ply) then return end
        
        for otherPly, state in pairs(playerFlashlightStates) do
            if IsValid(otherPly) and state and state.active then
                net.Start("rtx_flashlight_state")
                net.WriteEntity(otherPly)
                net.WriteBool(state.active)
                net.WriteUInt(state.color.r, 8)
                net.WriteUInt(state.color.g, 8)
                net.WriteUInt(state.color.b, 8)
                net.Send(ply)
            end
        end
    end)
end)

-- Clean up on death
hook.Add("PlayerDeath", "RTXFlashlight_Death", function(victim, inflictor, attacker)
    if playerFlashlightStates[victim] and playerFlashlightStates[victim].active then
        playerFlashlightStates[victim].active = false
        
        net.Start("rtx_flashlight_state")
        net.WriteEntity(victim)
        net.WriteBool(false)
        net.WriteUInt(playerFlashlightStates[victim].color.r, 8)
        net.WriteUInt(playerFlashlightStates[victim].color.g, 8)
        net.WriteUInt(playerFlashlightStates[victim].color.b, 8)
        net.Broadcast()
    end
end)

-- Set flashlight state (not toggle) for a player
local function SetPlayerFlashlight(ply, state, r, g, b)
    if not IsValid(ply) then return end
    
    -- Initialize if needed
    if not playerFlashlightStates[ply] then
        playerFlashlightStates[ply] = { active = false, color = Color(255, 240, 200) }
    end
    
    -- Update color if provided
    if r and g and b then
        playerFlashlightStates[ply].color = Color(r, g, b)
    end
    
    -- Only broadcast if state actually changed
    if playerFlashlightStates[ply].active ~= state then
        playerFlashlightStates[ply].active = state
        
        -- Broadcast to all clients
        net.Start("rtx_flashlight_state")
        net.WriteEntity(ply)
        net.WriteBool(state)
        net.WriteUInt(playerFlashlightStates[ply].color.r, 8)
        net.WriteUInt(playerFlashlightStates[ply].color.g, 8)
        net.WriteUInt(playerFlashlightStates[ply].color.b, 8)
        net.Broadcast()
    end
end

-- Intercept Source engine flashlight toggle and use RTX flashlight instead
local cv_override = CreateConVar("rtx_flashlight_override_default", "1", FCVAR_ARCHIVE, "Override default flashlight with RTX flashlight")

hook.Add("PlayerSwitchFlashlight", "RTXFlashlight_Override", function(ply, enabled)
    -- If override is disabled, allow default behavior
    if not cv_override:GetBool() then return end
    
    -- R19: the gamemode decides who may switch on (no flashlight for the dead or spectators), and a
    -- switch on waits out the cooldown; switching off is never refused
    if enabled and (not MayUseFlashlight(ply, true) or ToggleTooSoon(ply)) then return false end
    
    -- Initialize state if needed
    if not playerFlashlightStates[ply] then
        playerFlashlightStates[ply] = { active = false, color = Color(255, 240, 200) }
    end
    
    -- Set RTX flashlight to match the desired state
    local col = playerFlashlightStates[ply].color
    SetPlayerFlashlight(ply, enabled, col.r, col.g, col.b)
    
    -- Allow the engine to track flashlight state normally (for the hook to work correctly)
    -- but the visual effect won't appear because RTX will override it
    return true
end)

print("[RTX Flashlight] Server component loaded - multiplayer support enabled")
print("[RTX Flashlight] Default flashlight override: " .. (cv_override:GetBool() and "ENABLED" or "DISABLED"))
