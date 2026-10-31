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

local function read_current()
    if not file.Exists(CURRENT, "DATA") then return "", 0 end
    if file.Size(CURRENT, "DATA") > MAX_FILE_BYTES then return end
    local body = file.Read(CURRENT, "DATA")
    if not body then return end
    if body == "" then return body, 0 end
    -- Leave an unrelated, edited or incompatible file alone rather than mixing CSV schemas.
    if body:sub(1, #HEADER) ~= HEADER or body:sub(-1) ~= "\n" then return end
    local _, lines = body:gsub("\n", "")
    if lines - 1 > ROWS_PER_FILE then return end
    return body, lines - 1
end

local function sample()
    if not enabled:GetBool() or type(RemixResource) ~= "table" or
        type(RemixResource.GetVramStats) ~= "function" then return end
    local ok, stats = pcall(RemixResource.GetVramStats)
    if not ok or type(stats) ~= "table" then return end
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
    if not found then return end

    if rows == nil or rows >= ROWS_PER_FILE then
        local body, count = read_current()
        if not body then return end
        file.CreateDir("native-loader")
        if count >= ROWS_PER_FILE then
            file.Write(PREVIOUS, body)
            file.Write(CURRENT, HEADER)
            rows = 0
        else
            if body == "" then file.Write(CURRENT, HEADER) end
            rows = count
        end
    end
    file.Append(CURRENT, table.concat(values, ",") .. "\n")
    rows = rows + 1
end

-- Retry availability on every tick: the binary module can load after this autorun. Failed API or
-- file operations stay silent and never interrupt the game. Each append is a separate file write.
timer.Create("nativeloader_vram", 30, 0, function() pcall(sample) end)
