-- Startup advice, once per loader process, after the first map has drawn (R20-B, ADR 0117).
-- Never use RemixConfig.GetConfigVariable: it reads rtx.conf, before live graphics/DLSS presets.
-- GetUpscalingState is an optional live snapshot contract, documented beside this file. The current
-- shipped native module has no live getter: absent/unreadable snapshots deliberately show nothing.
local L = include("nativeloader/i18n.lua").L
local enabled = CreateClientConVar("nativeloader_upscaling_hint", "1", true, false,
    "Show the startup upscaling/frame generation hint when supported features are off")
local MARKER = "nativeloader_companion/upscaling_hint_start.txt"
local POLL, DELAY, ATTEMPTS = "nativeloader_upscaling_hint", 12, 25

local function status()
    local ok, value = pcall(function()
        local body = file.Read("native-loader/status.json", "DATA")
        return body and util.JSONToTable(body)
    end)
    if not ok or type(value) ~= "table" or value.schema ~= 1 then return end
    local activation = value.activation
    if type(activation) ~= "table" or activation.outcome ~= "active" then return end
    -- Neither a map-local Lua flag nor a permanent "already shown" bit has the right lifetime.
    -- The loader writes a different pid/UTC pair at each game start; it survives Lua map changes.
    if type(value.process_id) ~= "number" or value.process_id <= 0 or value.process_id % 1 ~= 0
        or type(value.utc) ~= "string" or not value.utc:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d.*Z$") then return end
    return activation, string.format("%.0f", value.process_id) .. " " .. value.utc
end

local function rtxGPU(activation)
    if activation.non_nvidia ~= false or type(activation.gpu_vendors) ~= "table" then return end
    local nvidia = false
    for _, vendor in ipairs(activation.gpu_vendors) do if vendor == 4318 then nvidia = true end end
    local tier = activation.performance_tier
    local adapter = type(tier) == "table" and tier.adapter
    if not nvidia or type(adapter) ~= "string" then return end
    adapter = adapter:upper()
    -- Unknown/workstation/future naming stays silent. A second NVIDIA adapter is insufficient:
    -- classify the selected performance-tier adapter, not an arbitrary GPU in the vendor list.
    local generation = adapter:match("%f[%w]RTX%s+([2345])%d%d%d%f[%D]")
    return generation and tonumber(generation)
end

local function snapshot()
    if type(RemixConfig) ~= "table" or type(RemixConfig.GetUpscalingState) ~= "function" then return end
    local ok, state = pcall(RemixConfig.GetUpscalingState)
    if not ok or type(state) ~= "table" or state.ready ~= true then return end
    local up, fg = state.upscaler, state.frame_generation
    if type(up) ~= "number" or up % 1 ~= 0 or up < 0 or up > 5
        or type(fg) ~= "number" or fg % 1 ~= 0 or fg < 0 or fg > 2 then return end
    return state
end

local function message(generation, state)
    if not generation then return end
    local up = state.upscaler == 0 and state.dlss_supported == true
    local dlfg = generation >= 4 and state.dlss_frame_generation_supported == true
    local fsrfg = state.fsr_frame_generation_supported == true
    local fg = state.frame_generation == 0 and (dlfg or fsrfg)
    if up and fg then
        if dlfg then
            return L("Upscaling and frame generation are off.\nRTX Remix > Remix settings, or Alt+X:\nChoose Upscaler: DLSS and Frame generation: DLSS-G.")
        end
        return L("Upscaling and frame generation are off.\nRTX Remix > Remix settings, or Alt+X:\nChoose Upscaler: DLSS and Frame generation: FSR 3.")
    elseif up then
        return L("Upscaling is off.\nRTX Remix > Remix settings, or Alt+X:\nChoose Upscaler: DLSS.")
    elseif fg then
        if dlfg then
            return L("Frame generation is off.\nRTX Remix > Remix settings, or Alt+X:\nChoose Frame generation: DLSS-G.")
        end
        return L("Frame generation is off.\nRTX Remix > Remix settings, or Alt+X:\nChoose Frame generation: FSR 3.")
    end
end

local attempts, finished = 0, false
local function finish(token)
    finished = true
    timer.Remove(POLL)
    file.CreateDir("nativeloader_companion")
    file.Write(MARKER, token)
    return file.Read(MARKER, "DATA") == token
end

local function check()
    if finished then return end
    attempts = attempts + 1
    local activation, token = status()
    if activation then
        if file.Read(MARKER, "DATA") == token then finished = true timer.Remove(POLL) return end
        local hints = GetConVar("cl_showhints")
        if not enabled:GetBool() or not hints or not hints:GetBool() then finish(token) return end
        local generation = rtxGPU(activation)
        if not generation then finish(token) return end
        local state = snapshot()
        if state then
            local text = message(generation, state)
            local recorded = finish(token) -- consume "both on" too; never nag at a later map
            if text and recorded then
                notification.AddLegacy(text, NOTIFY_HINT, 18)
                surface.PlaySound("ambient/water/drip1.wav") -- sandbox's hint sound
            end
            return
        end
        if attempts >= ATTEMPTS then finish(token) return end
    end
    if attempts >= ATTEMPTS then finished = true timer.Remove(POLL) end
end

local function safeCheck()
    local ok = pcall(check)
    if not ok then finished = true timer.Remove(POLL) end
end

hook.Add("InitPostEntity", POLL, function()
    -- Begin the delay only once the map actually draws, after the preset and optional tab replay.
    hook.Add("PostRender", POLL, function()
        hook.Remove("PostRender", POLL)
        timer.Simple(DELAY, function()
            safeCheck()
            if not finished then timer.Create(POLL, 2, ATTEMPTS - attempts, safeCheck) end
        end)
    end)
end)
