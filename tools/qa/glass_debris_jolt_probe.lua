-- MIT. Client-only, deliberate offline-QA entry point; run by Claude in a known test scene.
if SERVER then return end
if NLGlassDebrisProbe then NLGlassDebrisProbe.Cancel() end
local D = NLGlassDebris
if not D or not D.Stats then print("NL_GLASS_PROBE error: debris manager missing"); return end
local requested = math.floor(math.Clamp(tonumber(NL_GLASS_PROBE_COUNT) or 4000, 1, 8192))
local dropSeconds = math.Clamp(tonumber(NL_GLASS_PROBE_SECONDS) or 20, 5, 120)
local player = LocalPlayer()
if not IsValid(player) then print("NL_GLASS_PROBE error: local player missing"); return end
local origin = NL_GLASS_PROBE_ORIGIN or player:GetEyeTrace().HitPos
if not isvector(origin) then print("NL_GLASS_PROBE error: choose a floor origin"); return end
local saved, applied = {}, {}
local function set(name, value)
    local cv = GetConVar(name)
    if not cv then return end
    saved[name], applied[name] = cv:GetString(), tostring(value)
    RunConsoleCommand(name, tostring(value))
end
set("rtx_glass_debris_budget", requested)
set("rtx_glass_debris_lifetime", 0)
local phase, since, samples, elapsed, stopped = "init", RealTime(), {}, 0, false
local lastFrame = SysTime()
local function finish()
    if stopped then return end
    stopped = true
    hook.Remove("Think", "NLGlass.DebrisProbe")
    if not NL_GLASS_PROBE_KEEP then D.Clear() end
    for name, value in pairs(saved) do
        local cv = GetConVar(name)
        if cv and cv:GetString() == applied[name] then RunConsoleCommand(name, value) end
    end
    NLGlassDebrisProbe = nil
    print("NL_GLASS_PROBE done")
end
NLGlassDebrisProbe = {Cancel = finish}
local function percentile(sorted, p) return sorted[math.max(1, math.ceil(#sorted * p))] or 0 end
local function report()
    table.sort(samples)
    local sum = 0
    for _, value in ipairs(samples) do sum = sum + value end
    local s = D.Stats()
    print(string.format("NL_GLASS_PROBE phase=%s samples=%d mean_ms=%.3f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f backend=%s live=%d moving=%d sleeping=%d merged=%d batches=%d rebuilds=%d native_step_ms=%.3f",
        phase, #samples, sum / math.max(1, #samples), percentile(samples, .5), percentile(samples, .95),
        percentile(samples, .99), samples[#samples] or 0, D.Backend(), s.live, s.moving, s.sleeping, s.merged,
        s.batches, s.rebuilds, s.native.step_ms or 0))
end
local function begin(name)
    phase, since, samples = name, RealTime(), {}
    print("NL_GLASS_PROBE begin " .. name)
end
local function spawn(number)
    local perLayer = math.ceil(number / 4)
    local columns = math.ceil(math.sqrt(perLayer * 1.6))
    for layer = 0, 3 do
        local fragments = {}
        for j = 1, math.min(perLayer, number - layer * perLayer) do
            local x, y = ((j - 1) % columns - columns / 2) * 5, (math.floor((j - 1) / columns) - math.ceil(perLayer / columns) / 2) * 5
            fragments[#fragments + 1] = {poly = {{x - 2, y - 2}, {x + 2, y - 2}, {x + 2, y + 2}, {x - 2, y + 2}},
                thickness = .6, velocity = Vector(), spin = Vector(), seed = j + layer * perLayer}
        end
        D.Spawn({origin = origin + Vector(0, 0, 32 + layer * 16), angles = angle_zero,
            material = "rtx/replace_me/glassmat"}, fragments)
    end
end
D.Clear()
local initialized, reason = pcall(spawn, 1) -- Warm the backend before the empty-scene baseline.
if not initialized then print("NL_GLASS_PROBE error: " .. tostring(reason));finish();return end
print(string.format("NL_GLASS_PROBE requested=%d origin=%.2f,%.2f,%.2f drop_s=%.1f map=%s", requested, origin.x, origin.y, origin.z, dropSeconds, game.GetMap()))
local function think()
    local now = RealTime()
    local wall = SysTime()
    local frameMs = (wall - lastFrame) * 1000
    lastFrame = wall
    if phase == "init" then
        if D.Backend() ~= "none" and D.Stats().pending == 0 then D.Clear();begin("warmup")
        elseif now - since > 60 then print("NL_GLASS_PROBE error: backend import timeout");finish() end
        return
    end
    if phase == "warmup" then if now - since >= 2 then begin("baseline") end;return end
    if #samples < 30000 then samples[#samples + 1] = frameMs end
    elapsed = now - since
    if phase == "baseline" and elapsed >= 5 then
        report();begin("falling");spawn(requested)
        print("NL_GLASS_PROBE spawned=" .. D.Count())
    elseif phase == "falling" and elapsed >= dropSeconds then
        report();begin("settled")
    elseif phase == "settled" and elapsed >= 10 then
        report();finish()
    end
end
hook.Add("Think", "NLGlass.DebrisProbe", function()
    local ok, reason = pcall(think)
    if not ok then print("NL_GLASS_PROBE error: " .. tostring(reason));finish() end
end)
