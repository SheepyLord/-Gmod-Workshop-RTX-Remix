-- Local Remix VRAM telemetry, when the RTX fixes expose GetVramStats. Two hourly CSV segments
-- retain at most 240 samples across map changes and restarts. No API means no files or messages.
-- Documented in nativeloader_vram.lua.md beside this file.
if not CLIENT then return end

local enabled = CreateClientConVar("nativeloader_vram_telemetry", "1", true, false,
    "Record local Remix VRAM statistics every 30 seconds (at most two hours of samples)")
local CURRENT = "native-loader/vram.csv"
local PREVIOUS = "native-loader/vram.previous.csv"
local ROWS_PER_FILE = 120
local MAX_FILE_BYTES = 128 * 1024
-- Names and units match remixapi_VramStats and the fixes' Lua binding. A missing field in an older
-- module is an empty cell, not a zero. forkTextureCacheCount is a count; all other fields are bytes.
local FIELDS = {
    "driverBudgetBytes", "driverAllocatedBytes", "totalAllocatedBytes", "totalUsedBytes",
    "poolRetainedBytes", "usedReplacementGeometryBytes", "usedBufferBytes",
    "usedAccelerationStructureBytes", "usedOpacityMicromapBytes", "usedMaterialTextureBytes",
    "usedRenderTargetBytes", "forkTextureCacheCount", "usedAppTextureBytes", "usedAppBufferBytes",
}
local HEADER = "time_utc," .. table.concat(FIELDS, ",") .. "\n"
local rows
local failures = 0
local MAX_FAILURES = 3

cvars.AddChangeCallback("nativeloader_vram_telemetry", function(_, _, value)
    if value == "0" then failures = 0 end
end, "nativeloader_vram")

local function rotate_current()
    -- These are the companion's own segments. Rename even a large/damaged file without reading
    -- or repairing it, keeping its bytes for diagnosis until the next rotation.
    file.Delete(PREVIOUS)
    if file.Exists(PREVIOUS, "DATA") then return end
    file.Rename(CURRENT, PREVIOUS)
    if file.Exists(CURRENT, "DATA") or not file.Exists(PREVIOUS, "DATA") then return end
    return "", 0
end

local function read_current()
    if not file.Exists(CURRENT, "DATA") then return "", 0 end
    if file.Size(CURRENT, "DATA") > MAX_FILE_BYTES then return rotate_current() end
    local body = file.Read(CURRENT, "DATA")
    if not body then return end
    if body == "" then return body, 0 end
    if body:sub(1, #HEADER) ~= HEADER or body:sub(-1) ~= "\n" or
        body:find("\0", 1, true) or body:find("\r", 1, true) then return rotate_current() end
    local count = 0
    for line in body:sub(#HEADER + 1):gmatch("([^\n]*)\n") do
        if not line:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ,") then return rotate_current() end
        local cells = 0
        for cell in (line .. ","):gmatch("(.-),") do
            cells = cells + 1
            if cells > 1 and cell ~= "" and not cell:match("^%d+$") then return rotate_current() end
        end
        if cells ~= #FIELDS + 1 then return rotate_current() end
        count = count + 1
        if count >= ROWS_PER_FILE then return rotate_current() end
    end
    return body, count
end

local function sample()
    if not enabled:GetBool() then failures = 0 return end
    if failures >= MAX_FAILURES or type(RemixResource) ~= "table" or
        type(RemixResource.GetVramStats) ~= "function" then return end
    local ok, stats = pcall(RemixResource.GetVramStats)
    if not ok or type(stats) ~= "table" then failures = failures + 1 return end
    local values, found = { os.date("!%Y-%m-%dT%H:%M:%SZ") }, false
    for _, name in ipairs(FIELDS) do
        local value = stats[name]
        if type(value) == "number" and value >= 0 and value < math.huge then
            values[#values + 1] = string.format("%.0f", value)
            found = true
        else
            values[#values + 1] = ""
        end
    end
    if not found then failures = failures + 1 return end
    failures = 0

    if rows == nil or rows >= ROWS_PER_FILE then
        local body, count = read_current()
        if not body then return end
        file.CreateDir("native-loader")
        if body == "" then file.Write(CURRENT, HEADER) end
        rows = count
    end
    file.Append(CURRENT, table.concat(values, ",") .. "\n")
    rows = rows + 1
end

-- Retry availability: the binary module can load after this autorun. Stop after three failed API
-- calls, since the native binding warns on each failure. Off/on or a map/restart permits a retry.
-- File errors stay silent and never interrupt the game. Each append is a separate file write.
timer.Create("nativeloader_vram", 30, 0, function() pcall(sample) end)
