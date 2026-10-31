-- QA probe for an RTX field session (run with poc_session.py --lua ... --lua-shots N).
-- Prints short "NL_QA_<part> <json>" lines (the console cuts a line at about 4 KB) with what the
-- loader's companion set up, then tours a few views: each "NL_SHOT <label>" is answered by the
-- session driver with "nl_shot_taken <n>". Changes nothing archived: it only selects a weapon.
local function count(t) local n = 0 if istable(t) then for _ in pairs(t) do n = n + 1 end end return n end
local function cv(name) local c = GetConVar(name) return c and c:GetString() or false end
local function sample(t, limit)
    local out = {}
    if not istable(t) then return out end
    for key, value in pairs(t) do
        if #out >= limit then break end
        out[#out + 1] = string.sub(tostring(key) .. " = " .. (istable(value) and util.TableToJSON(value) or tostring(value)), 1, 200)
    end
    return out
end
local function emit(part, value) print("NL_QA_" .. part .. " " .. util.TableToJSON(value)) end

local guard = NativeLoaderRenderGuard
emit("GUARD", guard and {
    version = guard.version, installation = guard.installation, enabled = guard.enabled,
    blocked = count(guard.blocked), errors = count(guard.errors), cleanup_errors = count(guard.cleanup_errors),
} or {missing = true})
if guard then
    emit("GUARD_BLOCKED", sample(guard.blocked, 6))
    emit("GUARD_ERRORS", sample(guard.errors, 6))
    emit("GUARD_CLEANUP", sample(guard.cleanup_errors, 6))
end
emit("PARTS", {
    map = game.GetMap(), dxlevel = render.GetDXLevel(), sky = NATIVELOADER_SKY ~= nil,
    i18n = NATIVELOADER_I18N ~= nil, mmdhl = mmdhl ~= nil, advmat = AdvMat ~= nil, motion = MMDVMDNPC ~= nil,
    pseudoplayers = #ents.FindByClass("rtx_pseudoplayer"),
    weapon = IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetActiveWeapon()) and LocalPlayer():GetActiveWeapon():GetClass() or false,
})
emit("CVARS", {
    nativeloader_guard = cv("nativeloader_guard"), rtx_pseudoplayer = cv("rtx_pseudoplayer"),
    rtx_pseudoplayer_offset_z = cv("rtx_pseudoplayer_offset_z"), gmod_language = cv("gmod_language"),
    r_forcehwlight = cv("r_forcehwlight"), mat_softwareskin = cv("mat_softwareskin"), r_hwskin_setbones = cv("r_hwskin_setbones"),
    r_drawviewmodel = cv("r_drawviewmodel"), sv_cheats = cv("sv_cheats"), sv_allowcslua = cv("sv_allowcslua"),
})
local hooks = {}
for event, list in pairs(hook.GetTable()) do
    for id in pairs(list) do
        if string.find(string.lower(tostring(id)), "nativeloader", 1, true) then hooks[#hooks + 1] = event .. "/" .. tostring(id) end
    end
end
table.sort(hooks)
for first = 1, #hooks, 12 do emit("HOOKS", {unpack(hooks, first, math.min(first + 11, #hooks))}) end

local steps = {
    function() print("NL_SHOT spawn") end,
    function()
        RunConsoleCommand("use", "gmod_tool")
        timer.Simple(3, function()
            local w = IsValid(LocalPlayer()) and LocalPlayer():GetActiveWeapon()
            print("NL_QA_WEAPON " .. (IsValid(w) and w:GetClass() or "none"))
            RunConsoleCommand("nativeloader_toolgun_status")  -- [nativeloader] Toolgun screen {captures, draws, error}
            local g = NativeLoaderRenderGuard
            if g then
                emit("GUARD_AFTER_TOOLGUN", {blocked = count(g.blocked), errors = count(g.errors), cleanup = count(g.cleanup_errors)})
                emit("GUARD_ERRORS_AFTER", sample(g.errors, 6))
            end
            timer.Simple(0.5, function() print("NL_SHOT toolgun") end)
        end)
    end,
    function() print("NL_SHOT_DONE") end,
}
local index = 0
local function nextStep() index = index + 1 if steps[index] then steps[index]() end end
concommand.Add("nl_shot_taken", function() timer.Simple(0.5, nextStep) end)
timer.Simple(1, nextStep)
