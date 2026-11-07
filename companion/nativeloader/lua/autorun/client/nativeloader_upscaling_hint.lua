-- Startup advice, once per loader process, after the first map has drawn (R20-B, ADR 0117).
-- Never use RemixConfig.GetConfigVariable: it reads rtx.conf, before live graphics/DLSS presets.
-- GetUpscalingState is the optional live snapshot contract supplied by R20-E, documented beside
-- this file. Older native modules or runtimes deliberately stay silent when it is unavailable.
local L = include("nativeloader/i18n.lua").L
local enabled = CreateClientConVar("nativeloader_upscaling_hint", "1", true, false,
    L("Show upscaling and frame generation hint at startup"))
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

-- R22 (ADR 0129): the same advice in a notice at the top right, like the Model Hotloader's, so it is
-- not missed among the sandbox hints. It goes after NOTICE_SECONDS, or earlier with its close button.
local NOTICE_SECONDS, NOTICE_FONT, NOTICE_TITLE_FONT = 15, "NativeLoaderHintNotice", "NativeLoaderHintNoticeTitle"
local function noticeTop(width, px)
    -- Below another notice already in the top-right corner (the Hotloader's sits at y = 40): only
    -- notice-sized panels count, never a visible full-screen menu.
    local top = px(40)
    local world = type(vgui.GetWorldPanel) == "function" and vgui.GetWorldPanel()
    if not world or type(world.GetChildren) ~= "function" then return top end
    local left = ScrW() - width - px(20)
    for _ = 1, 4 do
        local moved = false
        for _, child in ipairs(world:GetChildren()) do
            if IsValid(child) and child:IsVisible() and not child.nativeloaderHintNotice then
                local x, y = child:GetPos()
                local w, h = child:GetSize()
                if w < ScrW() / 2 and h < ScrH() / 2 and x + w > left and y < top + px(110) and y + h > top then
                    top, moved = y + h + px(10), true
                end
            end
        end
        if not moved then break end
    end
    return top
end

local function showNotice(text)
    if type(vgui) ~= "table" or type(vgui.Create) ~= "function" or type(ScrW) ~= "function" then return end
    local scale = math.max(0.65, ScrH() / 1080) -- the companion's windows scale with the screen (4K)
    local function px(n) return math.floor(n * scale + 0.5) end
    surface.CreateFont(NOTICE_TITLE_FONT, { font = "Arial", size = px(19), weight = 700 })
    surface.CreateFont(NOTICE_FONT, { font = "Arial", size = px(17), weight = 400 })
    local width = math.min(px(500), ScrW() - px(40))
    local panel = vgui.Create("DPanel")
    panel.nativeloaderHintNotice = true
    panel:SetSize(width, px(120))
    panel:DockPadding(px(18), px(12), px(40), px(14))
    local born = SysTime()
    panel.Paint = function(_, w, h)
        draw.RoundedBox(px(6), 0, 0, w, h, Color(24, 26, 30, 235))
        surface.SetDrawColor(118, 185, 0, 255) -- the accent of the loading window and RTX Remix
        surface.DrawRect(0, 0, px(4), h)
    end
    local title, body
    local function fit(self)
        -- The wrapped body sets its height during its own layout: follow it.
        local tall = px(12) + title:GetTall() + body:GetTall() + px(14)
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
    panel.Think = function(self)
        local age = SysTime() - born
        self:SetAlpha(255 * math.Clamp(math.min(age / 0.25, (NOTICE_SECONDS - age) / 0.6), 0, 1))
        fit(self)
    end
    title = panel:Add("DLabel")
    title:Dock(TOP)
    title:SetTall(px(26))
    title:SetFont(NOTICE_TITLE_FONT)
    title:SetTextColor(Color(118, 185, 0))
    title:SetText("RTX Remix")
    body = panel:Add("DLabel")
    body:Dock(TOP)
    body:SetFont(NOTICE_FONT)
    body:SetTextColor(Color(235, 237, 240))
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    body:SetText(text)
    local close = panel:Add("DButton")
    close:SetText("\xC3\x97") -- the multiplication sign, as the Hotloader's notice uses
    close:SetFont(NOTICE_TITLE_FONT)
    close:SetSize(px(26), px(26))
    close.DoClick = function() panel:Remove() end
    panel.PerformLayout = function(self, w)
        close:SetPos(w - px(32), px(8))
        fit(self)
    end
    panel:SetPos(ScrW() - width - px(20), noticeTop(width, px))
    panel:SetAlpha(0)
    timer.Simple(NOTICE_SECONDS, function() if IsValid(panel) then panel:Remove() end end)
    return panel
end

local attempts, finished = 0, false
local function finish(token)
    finished = true
    timer.Remove(POLL)
    file.CreateDir("nativeloader_companion")
    file.Write(MARKER, token)
    return file.Read(MARKER, "DATA") == token
end

local function uiBusy()
    if type(gui) == "table" and type(gui.IsGameUIVisible) == "function" and gui.IsGameUIVisible() then return true end
    if type(vgui) == "table" and type(vgui.CursorVisible) == "function" and vgui.CursorVisible() then return true end
    if type(RemixConfig) == "table" and type(RemixConfig.GetUIState) == "function" then
        local ok, state = pcall(RemixConfig.GetUIState)
        local none = type(RemixConfig.UIState) == "table" and RemixConfig.UIState.None or 0
        return not ok or type(state) ~= "number" or state ~= none
    end
    return false
end

local function check()
    if finished then return end
    -- The first-run guide opens after eight seconds. Stock notifications sit behind it, so wait
    -- for an unobstructed map before reading/consuming the decision. Read again after the UI closes,
    -- rather than queuing stale "off" advice while the player changes settings in a menu.
    if uiBusy() then return end
    attempts = attempts + 1
    local activation, token = status()
    if activation then
        if file.Read(MARKER, "DATA") == token then finished = true timer.Remove(POLL) return end
        -- The RTX tab's checkbox turns both off. cl_showhints turns off sandbox hints only: the top-right
        -- notice is not one (R22, ADR 0129; the user's own game had cl_showhints 0, so it saw neither).
        if not enabled:GetBool() then finish(token) return end
        local hints = GetConVar("cl_showhints")
        local sandbox = hints ~= nil and hints:GetBool()
        local generation = rtxGPU(activation)
        if not generation then finish(token) return end
        local state = snapshot()
        if state then
            local text = message(generation, state)
            local recorded = finish(token) -- consume "both on" too; never nag at a later map
            if text and recorded then
                if sandbox then
                    notification.AddLegacy(text, NOTIFY_HINT, 18)
                    surface.PlaySound("ambient/water/drip1.wav") -- sandbox's hint sound
                end
                pcall(showNotice, text) -- a failed notice never costs the hint
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
            -- Menu waiting does not spend the 25 native-readiness attempts. The timer removes
            -- itself on any final decision/error; an open menu performs no file/snapshot reads.
            if not finished then timer.Create(POLL, 2, 0, safeCheck) end
        end)
    end)
end)
